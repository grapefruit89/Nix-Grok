---
meta:
  role: doc
  purpose: secrets-portal — Architektur-Entscheidungen für Secret-Rotation-Web-UI
  status: accepted
  date: 2026-07-09
  services: [secrets-portal]
  betrifft:
    - packages/secrets-portal/main.go
    - packages/secrets-portal/static/index.html
    - modules/20-security/2029-secrets-portal.nix
    - machines/q958/default.nix
    - lib/services-spec.nix
  docs:
    - docs/guides/GUIDE-secrets-portal.md
    - docs/adr/1031-caddy-zones-konzept.md
    - docs/adr/2024-systemd-creds-tpm.md
    - docs/superpowers/specs/2026-07-09-secrets-rotator-design.md
    - docs/superpowers/plans/2026-07-09-secrets-portal.md
  tags:
    - secrets
    - security
    - web-ui
    - go
    - systemd-creds
---

# ADR-1034: secrets-portal Architektur {#adr-1034-secrets-portal-architektur}

**Status:** Accepted
**Datum:** 2026-07-09

---

## Kontext {#kontext}

Secrets (CF-Token, Restic-Keys, VPN-Key, Usenet-Zugangsdaten) landen bisher in
`profile.local.nix` — einer gitignorierten Datei die manuell per SSH editiert werden
muss. Das ist fehleranfällig, erfordert Terminal-Zugang, und macht Rotation unbequem.

Ziel: Alle Secrets über den Browser setzen — einmalig beim Setup und zur Rotation —
ohne dass Secrets jemals den Server verlassen. Kein SSH nötig.

---

## Entscheidungen {#entscheidungen}

### 1. Einbahnstraße: Write-Only, niemals Read {#1-einbahnstrasse-write-only-niemals-read}

Das Portal gibt **keine Secret-Werte zurück**. Weder via API noch via UI.

`GET /api/secrets` liefert nur `"exists": true|false` (Existenz der `.cred`-Datei),
niemals den Inhalt. Das Frontend speichert nichts (kein localStorage, kein State).
Input-Felder werden nach erfolgreichem Submit geleert.

**Konsequenz:** Selbst wenn ein Angreifer im LAN die Seite öffnet — er sieht leere
Felder und Statusicons. Kein Angriffsziel für Secret-Exfiltration.

### 2. Go Binary statt Python/Bash {#2-go-binary-statt-pythonbash}

Go wird gewählt weil:
- Stdlib only, kein `vendorHash`-Problem bei nixpkgs-Updates
- Single binary, keine Runtime-Dependencies
- Eingebettetes HTML via `//go:embed` — ein Artefakt, eine Datei
- Einfache Concurrency für den Rebuild-Debounce-Timer (Goroutine + sync.Mutex)

Python wäre für eine einmalige UI einfacher gewesen, aber Go passt besser in die
bestehende nixpkgs-Paket-Infrastruktur (vgl. `grok-cli`).

### 3. Unix Socket + Caddy internal zone statt TCP-Port {#3-unix-socket-caddy-internal-zone-statt-tcp-port}

Der Service lauscht auf `/run/secrets-portal/secrets-portal.sock` (kein TCP).
Caddy proxied darauf mit `zone = "internal"` (ADR-1031) — das bedeutet:

- Erreichbar nur aus LAN-CIDRs (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12)
- URL: `https://secrets.{domain}` mit gültigem ACME-Zertifikat
- Kein offener TCP-Port, kein firewall-Loch nötig
- Caddy übernimmt TLS-Terminierung

**Warum nicht direkt TCP auf LAN-IP?** Der Unix-Socket erzwingt dass nur Caddy
(laut Caddy-Gruppe-Berechtigung) verbinden kann. TCP auf LAN-IP wäre breiter exponiert
und würde kein TLS ohne zusätzliche Konfiguration bekommen.

### 4. Zwei-Schritt Write: profile.local.nix + systemd-creds {#4-zwei-schritt-write-profilelocalnix-systemd-creds}

Bei jedem erfolgreichen Seal:

```text
1. systemd-creds encrypt → /var/lib/credstore.encrypted/{name}.cred  (sofort wirksam)
2. profile.local.nix atomar aktualisieren (tmp + rename)              (Persistenz)
3. q958-secrets-provision restart                                      (alle abhängigen creds)
4. Rebuild-Debounce-Timer (3 min) reset                               (Nix-Config sync)
```

**Warum beide?** systemd-creds allein überleben keinen `nixos-rebuild` (provision
überschreibt sie aus profile.local.nix). profile.local.nix allein wirkt erst nach
Rebuild. Beide zusammen: sofort wirksam UND persistent.

**Warum nicht nur provision restart?** Provision generiert aus einem Input mehrere
Outputs (CF-Token → ddns-updater-config.json + cloudflare_acme_env + cloudflare_api_token).
Der direkte systemd-creds Write ist zuverlässiger für den einfachen Fall.

### 5. Regex: Nur visuelles Feedback, kein Gate {#5-regex-nur-visuelles-feedback-kein-gate}

Regex-Pattern werden clientseitig ausgewertet:
- Match → Feld grün + auto-submit (500ms debounce)
- Kein Match → Feld neutral (kein Rot/Error bei leerem Feld)
- Button ist **immer** klickbar, unabhängig vom Regex-Status

**Warum kein Button-Disable bei Regex-Miss?** Key-Formate ändern sich (CF hat 2022
das Token-Format geändert). Ein hartes Disable würde den Workflow brechen ohne
sichtbaren Grund. Das Backend validiert ohnehin via echtem API-Call.

### 6. Rebuild-Debounce-Timer (3 Minuten) {#6-rebuild-debounce-timer-3-minuten}

Nach jedem erfolgreichen Seal startet/resettet ein Server-seitiger Timer. Feuert er:
`nixos-rebuild switch --flake /etc/nixos#q958 --impure`

**Warum?** Manche Secrets (z.B. `domain.base`) ändern Nix-Build-Zeit-Werte
(Caddy vHosts, ACME-Domain). Ohne Rebuild wirken diese Änderungen nicht. Der Debounce
stellt sicher dass nicht bei jedem Key-Eintrag sofort ein 2-Minuten-Rebuild startet.

**Was wenn der Rebuild scheitert?** profile.local.nix hat den Key bereits — der
nächste manuelle Rebuild (oder nächste Portal-Nutzung) triggert wieder.

### 7. Validation vor Write — immer {#7-validation-vor-write-immer}

Kein Key wird in systemd-creds oder profile.local.nix geschrieben ohne:
- **API-Validator vorhanden:** HTTP-Call muss `expect_status` zurückgeben
- **TCP-Validator:** TCP-Connect muss aufgebaut werden können
- **Kein Validator:** Regex-Match ist ausreichend (für WireGuard-Key, Domain, etc.)

**Ausnahme:** profilePattern-Write kann trotzdem stattfinden wenn der systemd-creds-Write
erfolgreich war aber writeProfile() fehlschlägt (Datei-Berechtigungsproblem etc.) — das
wird nur geloggt, nicht als HTTP-Fehler zurückgegeben. Der Key ist in creds gesiegelt,
das ist die wichtigere Garantie.

---

## Was dieses ADR NICHT entscheidet {#was-dieses-adr-nicht-entscheidet}

- **Phase 2 (Stufe 9+):** TPM-sealed Creds Rotation ohne profile.local.nix — separates ADR
- **Secret-Anzeige:** Wird bewusst nie implementiert (Design-Constraint)
- **Vollständige profile.local.nix Verwaltung:** Nur die explizit definierten Felder
  mit `profilePattern` werden geschrieben; der Rest (MQTT-Passwörter, HA-Admin-PW etc.)
  bleibt manuell

---

## Erweiterung {#erweiterung}

Neues Secret hinzufügen: **ein Eintrag in `machines/q958/default.nix`** unter
`my.services.secrets-portal.secrets`. Kein Code-Änderung nötig solange:
- HTTP-Validator ausreicht
- Das Regex-Pattern den Key eindeutig identifiziert

Für neue Validator-Typen (z.B. S3-Connect, SMTP-Check): `main.go handleValidate()`
erweitern — das ist die einzige Go-Code-Änderung.

Siehe: `docs/guides/GUIDE-secrets-portal.md`

## Siehe auch {#siehe-auch}

- [GUIDE-secrets-portal](../guides/GUIDE-secrets-portal.md)
- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md)
- [ADR-1031 — Caddy-Zonen-Konzept](1031-caddy-zones-konzept.md)
