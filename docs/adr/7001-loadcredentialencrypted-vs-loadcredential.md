---
meta:
  role: doc
  purpose: ADR-7001 — LoadCredentialEncrypted vs LoadCredential für systemd-creds
  status: accepted
  date: 2026-07-09
  error_pattern: "MQTT.*Not authorized|homeassistant_mqtt_password missing|CREDENTIALS_DIRECTORY not set"
  quick_fix: "Check LoadCredentialEncrypted in home-assistant-mqtt-provision.service; wc -c $CREDENTIALS_DIRECTORY/homeassistant_mqtt_password (should be 12, not 527)"
  services:
    - home-assistant-mqtt-provision
    - home-assistant
  betrifft:
    - modules/70-home-automation/home-assistant.nix
  docs:
    - docs/adr/2024-systemd-creds-tpm.md
    - docs/adr/7002-ha-storage-provisioning.md
  tags:
    - adr
    - systemd
    - secrets
    - home-automation
    - mqtt
---

# ADR-7001: LoadCredentialEncrypted für verschlüsselte systemd-creds {#adr-7001}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-09 |
| **Host** | q958 |

---

## Kontext {#kontext}

- Secrets auf q958 werden via `systemd-creds encrypt` versiegelt und in `/var/lib/credstore.encrypted/*.cred` abgelegt ([ADR-2024](2024-systemd-creds-tpm.md))
- Das `home-assistant-mqtt-provision`-Script benötigt das MQTT-Passwort im Klartext, um es in `/var/lib/hass/.storage/core.config_entries` zu schreiben
- Im Service-Unit war `LoadCredential=homeassistant_mqtt_password:...` konfiguriert
- Symptom: HA schrieb einen 527-Zeichen-Blob als MQTT-Passwort in `.storage`, Mosquitto lehnte mit "Not authorized" ab

## Entscheidung {#entscheidung}

**Für systemd-creds-verschlüsselte `.cred`-Dateien muss `LoadCredentialEncrypted=` statt `LoadCredential=` verwendet werden.**

### Warum das der Unterschied ist {#unterschied}

`systemd-creds encrypt` produziert eine base64-ähnliche ASCII-Datei (~527 Bytes für ein 12-Byte-Passwort):

```text
k6iUCUh0RJCQyvL8k8q1UyAAAAABAAAADAAAABAAAADAW8yt...
```

Die zwei Direktiven verhalten sich grundlegend verschieden:

| Direktive | Was landet in `$CREDENTIALS_DIRECTORY/name` |
|-----------|----------------------------------------------|
| `LoadCredential=name:path` | Roher Dateiinhalt — die 527 Bytes der `.cred`-Datei |
| `LoadCredentialEncrypted=name:path` | Entschlüsselter Klartext — die 12 Bytes `#1Baumeister` |

Der Fehler: das Provision-Script bekam 527 verschlüsselte Bytes, rief `.strip()` darauf auf und schrieb die komplette Blob als MQTT-Passwort in HA's `.storage`. Mosquitto sah diesen 527-Zeichen-String als Passwort und lehnte ab.

**`LoadCredential=` ist für Klartext-Dateien** (z.B. Hash-Dateien, bereits entschlüsselte Werte).
**`LoadCredentialEncrypted=` ist für Dateien, die via `systemd-creds encrypt` versiegelt wurden.**

### Fix in home-assistant.nix {#fix-nix}

```nix
# VORHER (falsch — gibt 527 verschlüsselte Bytes): {#vorher-falsch-gibt-527-verschluesselte-bytes}
LoadCredential = [
  "homeassistant_mqtt_password:/var/lib/credstore.encrypted/homeassistant_mqtt_password.cred"
];

# NACHHER (korrekt — gibt 12 Bytes Klartext): {#nachher-korrekt-gibt-12-bytes-klartext}
LoadCredentialEncrypted = [
  "homeassistant_mqtt_password:/var/lib/credstore.encrypted/homeassistant_mqtt_password.cred"
];
```bash

### Fallback entfernt (Sicherheitsprinzip) {#fallback}

Das Script hatte einen Silent-Fallback auf `/var/lib/secrets/homeassistant_mqtt_password` wenn `CREDENTIALS_DIRECTORY` nicht gesetzt war:

```python
# VORHER — maskiert Konfigurationsfehler still: {#vorher-maskiert-konfigurationsfehler-still}
_creds = os.environ.get("CREDENTIALS_DIRECTORY", "")
PASSWORD_FILE = Path(_creds) / "homeassistant_mqtt_password" if _creds else Path("/var/lib/secrets/...")

# NACHHER — scheitert laut bei Fehlkonfiguration: {#nachher-scheitert-laut-bei-fehlkonfiguration}
_creds = os.environ.get("CREDENTIALS_DIRECTORY")
if not _creds:
    raise SystemExit("CREDENTIALS_DIRECTORY not set — LoadCredentialEncrypted failed")
PASSWORD_FILE = Path(_creds) / "homeassistant_mqtt_password"
```

## Diagnose {#diagnose}

**Symptom:** HA verbindet sich nicht mit Mosquitto, "Not authorized" bleibt dauerhaft — auch nach korrekt gesetztem Passwort.

```bash
# Passwort in .storage prüfen: {#passwort-in-storage-pruefen}
sudo grep -o '"password":"[^"]*"' /var/lib/hass/.storage/core.config_entries
# Korrekt:  "password":"#1Baumeister"  (12 Zeichen) {#korrekt-password1baumeister-12-zeichen}
# Buggy:    "password":"k6iUCUh0..."   (526 Zeichen) {#buggy-passwordk6iucuh0-526-zeichen}
```bash

```bash
# Wie groß ist die Credential im CREDENTIALS_DIRECTORY? {#wie-gross-ist-die-credential-im-credentials_directory}
sudo systemd-run --wait --pipe \
  -p LoadCredentialEncrypted=homeassistant_mqtt_password:/var/lib/credstore.encrypted/homeassistant_mqtt_password.cred \
  -p Type=oneshot \
  /bin/sh -c 'wc -c "$CREDENTIALS_DIRECTORY/homeassistant_mqtt_password"'
# Erwartet: 12 / Buggy: 527 {#erwartet-12-buggy-527}
```

<details>
<summary>Vollständige Diagnose-Befehle</summary>

```bash
# Credential-Datei raw ansehen (ist base64-ähnlich ASCII, kein Binär): {#credential-datei-raw-ansehen-ist-base64-aehnlich-ascii-kein-binaer}
sudo od -c /var/lib/credstore.encrypted/homeassistant_mqtt_password.cred | head -3

# Manuell entschlüsseln: {#manuell-entschluesseln}
sudo systemd-creds decrypt --name=homeassistant_mqtt_password \
  /var/lib/credstore.encrypted/homeassistant_mqtt_password.cred -

# Service-Unit inspizieren: {#service-unit-inspizieren}
sudo systemctl cat home-assistant-mqtt-provision.service | grep LoadCred
# Muss "LoadCredentialEncrypted" zeigen, nicht "LoadCredential" {#muss-loadcredentialencrypted-zeigen-nicht-loadcredential}
```bash

</details>

## Fix {#fix}

```bash
# 1. Service-Unit prüfen {#1-service-unit-pruefen}
sudo systemctl cat home-assistant-mqtt-provision.service | grep LoadCred

# 2. home-assistant.nix: LoadCredential → LoadCredentialEncrypted {#2-home-assistantnix-loadcredential-loadcredentialencrypted}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure

# 3. Verifikation {#3-verifikation}
sudo grep -o '"password":"[^"]*"' /var/lib/hass/.storage/core.config_entries
# → "password":"#1Baumeister" {#password1baumeister}
sudo journalctl -u mosquitto --since "1 minute ago" --no-pager | grep homeassistant
# → New client connected ... u'homeassistant' (kein auth error) {#new-client-connected-uhomeassistant-kein-auth-error}
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Provision-Script bekommt immer Klartext — kein Decoding-Overhead
- Fehlkonfiguration scheitert laut (kein stiller Fallback mehr)
- `.storage` enthält nach jedem `nixos-rebuild switch` das korrekte Passwort

### Negativ / Trade-offs {#negativ}

- `LoadCredentialEncrypted=` benötigt den Host-TPM-Key — `.cred`-Dateien sind host-gebunden
- Wenn die `.cred`-Datei fehlt, scheitert der Provision-Service laut und HA startet nicht

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Service-Definition | `modules/70-home-automation/home-assistant.nix` |
| Provision-Script | `modules/70-home-automation/home-assistant.nix` (eingebettet) |
| Encrypted Credential | `/var/lib/credstore.encrypted/homeassistant_mqtt_password.cred` |

### Verifikation {#verifikation}

```bash
sudo systemctl cat home-assistant-mqtt-provision.service | grep "LoadCredentialEncrypted"
```nix

## Alternativen verworfen {#alternativen}

- **Plaintext-Fallback beibehalten** — `/var/lib/secrets/homeassistant_mqtt_password` immer verwenden, `LoadCredential` entfernen. Funktioniert, aber schreibt Klartext dauerhaft auf Disk und umgeht das Credentials-System. Abgelehnt.
- **Script entschlüsselt selbst** — Python liest `.cred` und ruft `systemd-creds`-Bibliothek auf. Keine Bibliothek in nixpkgs ohne Aufwand verfügbar. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-09 | Initial — Root-Cause gefunden, `LoadCredentialEncrypted` deployed, MQTT läuft |

## Siehe auch {#siehe-auch}

- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — Architekturentscheidung für das Credentials-System
- [ADR-7002 — HA .storage Provisioning](7002-ha-storage-provisioning.md) — Race conditions und Service-Reihenfolge
