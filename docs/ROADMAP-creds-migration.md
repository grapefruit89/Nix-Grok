# Plan: Zone-Restrukturierung + systemd-creds Migration

## Context

Zwei unabhängige Änderungen, die einzeln deployed werden können:

**A) Zone-Restrukturierung:** Dienste die nur intern gebraucht werden (sonarr, radarr, 
prowlarr, lidarr, readarr, vaultwarden) sind aktuell in `family-pocketid` (WAN mit SSO).
Sie müssen zu `internal` (LAN/Netbird-only via `private_admin` Snippet) verschoben werden.

**B) systemd-creds Migration:** Aktuell werden alle 34 Secrets als Klartext in 
`/var/lib/secrets/` gespeichert — erzeugt von `secrets.nix` + `media-secrets.nix`, 
die Werte direkt aus `profile.local.nix` in Shell-Scripts interpolieren und damit 
in die Nix-Store-Derivationen einbetten (world-readable!). Ziel: alle Secrets auf 
`LoadCredentialEncrypted=` umstellen, sodass nichts mehr im Nix-Store landet.
TPM-Versiegelung folgt als Schritt 2 (ein Flip: `useTpm = true`).

---

## Wichtige Vorbefunde (Explore-Agents)

- **Jellyfin App-Bypass bereits implementiert:** `@jellyfin_client header_regexp X-Emby-Authorization (?i)MediaBrowser` in `caddy-ingress.nix:68` — native Apps (Infuse, iOS/Android) umgehen SSO korrekt. Kein Handlungsbedarf.
- **`my.creds` Infrastruktur vorhanden aber leer:** `05-creds.nix` ist fertig, `my.creds.keys = []`, `my.creds.enable = erstAb 9` (aktuell stufe 8 → deaktiviert).
- **Secrets landen im Nix-Store:** `secrets.nix`/`media-secrets.nix` interpolieren `profile.local.nix`-Werte in Shell-Scripts → `/nix/store/*/activate` enthält Klartext-Secrets. systemd-creds behebt das.
- **24 Dateien betroffen** für vollständige Migration (Explore-Agent Analyse).

---

## Teil A: Zone-Restrukturierung

### Datei: `/etc/nixos/lib/services-spec.nix`

**Definitiv zu `internal` (LAN/Netbird-only):**

| Service | Aktuell | Neu |
|---------|---------|-----|
| sonarr | family-pocketid | internal |
| radarr | family-pocketid | internal |
| prowlarr | family-pocketid | internal |
| lidarr | family-pocketid | internal |
| readarr | family-pocketid | internal |
| vaultwarden | family-pocketid | internal |

**⚠️ TBD — User muss entscheiden (hat "Ausnahmen gibt es" angegeben):**

homepage, filebrowser, open-webui, paperless, shiori, home-assistant, zigbee-stack, amp.  
→ Vorschlag: alle zu internal, bis User Ausnahmen benennt. Kein Risk: mit Netbird 
  aus dem Netz erreichbar.

**Bleibt WAN (family-pocketid):**
jellyfin, jellyseerr, audiobookshelf, navidrome, pocket-id.

### Implementierung

Nur `services-spec.nix` ändern — eine Zeile pro Service. Der Rest (Caddy-Config-Generierung) 
passiert automatisch über `caddy-ingress.nix`'s `genZoneVhost`.

```nix
# vorher:
sonarr = { port = ports.sonarr; zone = "family-pocketid"; ... };
# nachher:
sonarr = { port = ports.sonarr; zone = "internal"; ... };
```

### Verification A
```bash
sudo nixos-rebuild dry-build --flake /etc/nixos#q958 --impure
# Nach switch: curl -s https://sonarr.DOMAIN → 403 Forbidden von außen
# Von LAN/Netbird: weiterhin erreichbar
```

---

## Teil B: systemd-creds Migration

### Kritische Reihenfolge

Die Migration MUSS folgende Invariante einhalten:  
**Kein Service darf nach einem `nixos-rebuild switch` abstürzen.**  
→ Doppel-Betrieb: Während der Migration halten Services SOWOHL `EnvironmentFile=/var/lib/secrets/X.env` 
  ALS AUCH `LoadCredentialEncrypted` + `EnvironmentFile=%d/X.env`. Erst wenn alle Services 
  migriert und getestet sind, werden die alten `/var/lib/secrets/` Referenzen und die 
  Provision-Skripte entfernt.

### ⚠️ PFLICHT VOR SCHRITT 3: `%d` in EnvironmentFile empirisch verifizieren

Das gesamte Pattern-A (Mehrheit aller Services) basiert darauf dass `EnvironmentFile = "%d/X.env"` 
funktioniert — d.h. dass systemd `%d` in `EnvironmentFile=` zu `$CREDENTIALS_DIRECTORY` expandiert 
und die Credential-Datei **vor** dem EnvironmentFile-Laden materialisiert ist.

**Muss vor Schritt 3 einmalig getestet werden:**
```bash
# Testcredential anlegen:
printf 'FOO=bar\n' | sudo systemd-creds encrypt \
  --name=test.env - /var/lib/credstore.encrypted/test.env.cred

# Transiente Unit testen:
sudo systemd-run --unit=cred-test \
  -p LoadCredentialEncrypted="test.env:/var/lib/credstore.encrypted/test.env.cred" \
  -p "EnvironmentFile=%d/test.env" \
  --wait /bin/sh -c 'echo "FOO=$FOO"'
sudo journalctl -u cred-test | grep FOO
```

- Ergebnis `FOO=bar` → Pattern-A wie geplant umsetzen.
- Ergebnis leer/Fehler → Fallback: `ExecStartPre` kopiert Credential in tmpfs, 
  EnvironmentFile liest von dort. Alle Pattern-A Services müssen dann anders gebaut werden.

**Kein Schritt 3 starten ohne positives Testergebnis.**

---

### Schritt 0: Migrations-Skript schreiben

Neues Skript: `/etc/nixos/scripts/migrate-secrets-to-creds.sh`

```bash
#!/usr/bin/env bash
# Verschlüsselt alle /var/lib/secrets/* → /var/lib/credstore.encrypted/*.cred
# Beim ersten Run: host-key. Nach useTpm=true: --with-key=tpm2 (nochmal laufen lassen).
set -euo pipefail

STORE="/var/lib/credstore.encrypted"
SECRETS="/var/lib/secrets"
TPM_FLAG="${TPM_FLAG:-}"  # export TPM_FLAG=--with-key=tpm2 für TPM-Migration

mkdir -p "$STORE"
chmod 700 "$STORE"

for f in "$SECRETS"/*; do
  name=$(basename "$f")
  out="$STORE/${name}.cred"
  echo "Versiegele: $name → $out"
  systemd-creds encrypt $TPM_FLAG --name="$name" "$f" "$out"
done
echo "Fertig: $(ls "$STORE"/*.cred | wc -l) Credentials versiegelt."
```

Ausführen BEVOR der erste rebuild mit creds:
```bash
sudo bash /etc/nixos/scripts/migrate-secrets-to-creds.sh
```

### Schritt 1: Infrastruktur aktivieren (rollout.nix + 05-creds.nix)

**`machines/q958/rollout.nix`:**
```nix
# war: my.creds.enable = erstAb 9;
my.creds.enable = erstAb 8;
```

**`modules/00-core/05-creds.nix`** — `my.creds.keys` mit allen Secret-Namen füllen:
```nix
keys = [
  "sonarr.env" "radarr.env" "prowlarr.env" "lidarr.env" "readarr.env"
  "grafana.env" "navidrome-oidc.env" "jellyfin-oidc.env"
  "vaultwarden.env" "shiori.env" "zigbee2mqtt.env"
  "oauth2-proxy.env" "oauth2-proxy-cookie-secret"
  "cloudflare_acme_env" "cloudflare_api_token"
  "restic_password" "restic_s3_creds" "restic_mega_creds"
  "gatus_ssh_key" "hermes.env" "context7.env" "nvidia_nim_api_key"
  "homeassistant_mqtt_password" "mosquitto_password" "mosquitto_hass_password"
  "privado_private_key" "privado.env" "netbird_setup_key"
  "netbird-mgmt-encryption-key"
  "sabnzbd_api_key" "treasuremaps_api_key"
  "prowlarr_api_key" "sonarr_api_key" "radarr_api_key"
];
```

### Schritt 2: service-factory.nix erweitern (optional aber sauber)

Neuer Parameter `credentials ? []` in `mkService`:
```nix
mkService { 
  credentials ? [],  # Liste von Credential-Namen (ohne .cred Extension)
  ...
}
# Generiert:
LoadCredentialEncrypted = map (n: "${n}:${cfg.storeDir}/${n}.cred") credentials;
```

Vorteil: Services können sauber deklarieren was sie brauchen, statt `extraSystemd` zu hacken.

### Schritt 3: Pattern-A Services migrieren (EnvironmentFile → LoadCredentialEncrypted)

**Pro Service: 2 Zeilen hinzufügen, 1 Zeile ändern:**
```nix
# ALT:
EnvironmentFile = [ "/var/lib/secrets/${name}.env" ];

# NEU (Übergangszustand — beide Quellen aktiv):
LoadCredentialEncrypted = [ "${name}.env:${credStore}/${name}.env.cred" ];
EnvironmentFile = [ "%d/${name}.env" ];
# ALT-Zeile entfernen
```

**Reihenfolge nach Risiko (niedrig → hoch):**

| Priorität | Datei | Services | Muster |
|-----------|-------|----------|--------|
| 1 | `arr-helper.nix` | sonarr, radarr, prowlarr, lidarr, readarr (5 auf einmal) | EnvironmentFile → %d |
| 2 | `23-acme.nix` | ACME/Caddy | environmentFile → %d |
| 3 | `55-navidrome.nix` | navidrome | EnvironmentFile optional |
| 4 | `42-logging.nix` | grafana | EnvironmentFile optional |
| 5 | `61-core.nix` | vaultwarden (2x!), shiori | EnvironmentFile |
| 6 | `2028-oauth2-proxy.nix` | oauth2-proxy | keyFile + secretFile |
| 7 | `33-backup.nix` | restic (3 Credentials) | passwordFile, environmentFile |
| 8 | `70-home-automation/zigbee-stack.nix` | zigbee2mqtt | EnvironmentFile |

### Schritt 4: Pattern-B Services (Einzelwerte in Scripts)

Komplexer: Scripts lesen `cat /var/lib/secrets/api_key`. Muster:
```nix
# Service Unit bekommt:
LoadCredentialEncrypted = "api_key:${credStore}/api_key.cred";
# Script liest:
API_KEY=$(cat "$CREDENTIALS_DIRECTORY/api_key")
# statt:
API_KEY=$(cat /var/lib/secrets/api_key)
```

Betroffene Dateien (nach Aufwand):
1. `1003-gateway.nix` — cloudflare_api_token in Shell-Script
2. `51-jellyfin.nix` — jellyfin-oidc.env (grep in Activation-Script)
3. `hermes.nix` — context7.env, nvidia_nim_api_key
4. `41-gatus.nix` — gatus_ssh_key (SSH-Key wird in activation kopiert)
5. `1096-vpn.nix` — privado_private_key, netbird_setup_key
6. `70-home-automation/home-assistant.nix` — homeassistant_mqtt_password (Python-Path)
7. `56-arr-sync/` (3 Dateien) — apiKeyFile-Pfade in Sync-Scripts

**Sonderfall Mosquitto:** `hashedPasswordFile` ist NixOS-Modul-Option die einen Dateipfad erwartet.
Lösung: `ExecStartPre` kopiert Credential aus `$CREDENTIALS_DIRECTORY` an erwarteten Ort:
```nix
ExecStartPre = "+${pkgs.writeShellScript "copy-mosquitto-creds" ''
  install -m 600 "$CREDENTIALS_DIRECTORY/mosquitto_password" /run/mosquitto/password
''}";
```

### Schritt 5: Provision-Infrastruktur entfernen (erst NACH vollständigem Test)

Nur wenn alle Services erfolgreich mit `LoadCredentialEncrypted` laufen:
1. `machines/q958/secrets.nix` — Aktivierungs-Skript entfernen (oder auf no-op reduzieren)
2. `machines/q958/media-secrets.nix` — Dasselbe
3. `modules/30-storage/30-storage.nix` — `/var/lib/secrets` aus Impermanence entfernen, 
   `/var/lib/credstore.encrypted` hinzufügen
4. `profile.local.nix` — bleibt als menschlesbare Quelle der Klartext-Werte (gitignored, 
   nur für Notfall-Re-Encryption gebraucht)

### Schritt 6 (später): TPM-Versiegelung

⚠️ **ACHTUNG:** Schritt 5 hat `/var/lib/secrets/` entfernt — das Migrationsskript kann nicht 
mehr von dort lesen. TPM-Re-Seal muss aus den bestehenden Host-Key `.cred`-Dateien erfolgen 
(decrypt → re-encrypt):

```bash
# TPM-Re-Seal aus bestehenden Host-Key-Credentials:
STORE="/var/lib/credstore.encrypted"
for cred in "$STORE"/*.cred; do
  name=$(basename "$cred" .cred)
  echo "Re-versiegele mit TPM: $name"
  systemd-creds decrypt "$cred" - | \
    systemd-creds encrypt --with-key=tpm2 --name="$name" - "$cred"
done
```

```nix
# rollout.nix:
my.creds.useTpm = true;  # war: false
```

```bash
sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure
```

---

## Deployment-Reihenfolge (gesamt)

```
1. Teil A (Zone): services-spec.nix ändern → dry-build → switch → testen
2. Migrationsskript schreiben + committen (noch nicht ausführen)
3. Teil B Schritt 0: sudo bash migrate-secrets-to-creds.sh  ← außerhalb von nix!
4. Teil B Schritt 1: rollout.nix + 05-creds.nix → dry-build → switch → activation zeigt fehlende .cred
5. Teil B Schritt 2: service-factory erweitern (optional)
6. Teil B Schritt 3: Pattern-A Services migrieren (arr-helper zuerst) → switch → testen
7. Teil B Schritt 4: Pattern-B Services → switch → testen
8. Teil B Schritt 5: Provision-Skripte entfernen → switch → LANGER Test
9. Später: Schritt 6 TPM
```

## Kritische Risiken

| Risiko | Mitigation |
|--------|-----------|
| Credential-Datei fehlt beim Service-Start | Migrationsskript VOR rebuild ausführen; `my.creds.keys` Check gibt Warnung |
| `%d` in EnvironmentFile nicht unterstützt | Empirischer Test VOR Schritt 3 Pflicht (Testunit oben) |
| **Host-Key + Impermanence bei Stufe 9:** Wenn Stufe 9 erreicht wird BEVOR TPM aktiv ist, löscht Impermanence `/var/lib/systemd/credential.secret` (den Host-Key) → alle Credentials undecryptbar → kompletter Service-Ausfall beim Booten | **Option A:** `/var/lib/systemd/credential.secret` explizit in Impermanence-Persist-Pfade aufnehmen (als Übergang). **Option B (bevorzugt):** TPM (Schritt 6) ist HARTE Voraussetzung vor Stufe-9-Switch. Stufe 9 nicht erhöhen ohne `useTpm = true`. |
| Mosquitto/oauth2-proxy erwarten feste Pfade | ExecStartPre copy-Wrapper (dokumentiert in Schritt 4) |
| Secrets versehentlich aus `/var/lib/secrets/` entfernt vor Migration | Provision-Skripte bleiben bis Schritt 5 aktiv |
| TPM-Re-Seal hat keine Quelle nach Schritt 5 | Schritt 6 nutzt decrypt→re-encrypt aus bestehenden .cred (oben dokumentiert) |
| Credential-Name Mismatch: `--name=X` muss exakt `LoadCredentialEncrypted=X:...` matchen | Invariante: Dateiname ohne `.cred` = systemd credential ID. Überall gleich benennen. |

## Verification (gesamt)

```bash
# Nach Teil A:
curl -s -o /dev/null -w "%{http_code}" https://sonarr.DOMAIN  # → 403

# Nach Teil B Schritt 3 (am Beispiel sonarr):
sudo systemctl status sonarr  # Active: active (running)
sudo journalctl -u sonarr -n 20  # keine Credential-Fehler
sudo systemd-creds decrypt /var/lib/credstore.encrypted/sonarr.env.cred -  # zeigt entschlüsselten Inhalt

# Gesamt-Check:
sudo systemctl --failed  # keine failed units
```
