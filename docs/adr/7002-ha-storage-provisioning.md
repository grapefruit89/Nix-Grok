---
meta:
  role: doc
  purpose: ADR-7002 — HA .storage Provisioning — Muster, Race Conditions, Service-Reihenfolge
  status: accepted
  date: 2026-07-09
  error_pattern: "MQTT.*Not authorized|smlight.*entry.*overwrite|provision.*concurrent"
  quick_fix: "systemctl status home-assistant-mqtt-provision home-assistant-smlight-provision — beide müssen active (exited) sein BEVOR home-assistant.service startet"
  services:
    - home-assistant-mqtt-provision
    - home-assistant-smlight-provision
    - home-assistant
  betrifft:
    - modules/70-home-automation/home-assistant.nix
  docs:
    - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
  tags:
    - adr
    - home-automation
    - provisioning
    - systemd
    - mqtt
    - race-condition
---

# ADR-7002: HA .storage Provisioning — Muster, Race Conditions, Reihenfolge {#adr-7002}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-09 |
| **Host** | q958 |

---

## Kontext {#kontext}

- Home Assistant ≥2026 verwaltet Integrationen (MQTT, SMLIGHT) nicht mehr in `configuration.yaml`, sondern ausschließlich in `.storage/core.config_entries` (JSON)
- NixOS-Rebuild überschreibt diese Datei nicht automatisch — Provisioning muss via Oneshot-Services erfolgen
- Zwei Services schreiben in dieselbe Datei: `home-assistant-mqtt-provision` und `home-assistant-smlight-provision`
- Beide Services liefen zunächst parallel → Race Condition; außerdem gab es einen Filterfehler im Script

## Entscheidung {#entscheidung}

**Provisioning-Services für `.storage/core.config_entries` müssen sequenziell laufen und via explizite `after/wants`-Kette geordnet werden.**

### .storage-Eintrag-Muster {#eintrag-muster}

Jede Integration bekommt einen deterministischen `entry_id` (nicht HA's auto-generierte ULIDs), der bei jedem Rebuild wiederverwendet wird:

```python
ENTRY_ID = "q958mqttmosquitto001"   # Format: <host><domain><kurzname><version>
```text

Der Provision-Script-Ablauf:

```python
# Lesen → filtern (nur eigenen Entry entfernen) → eigenen Entry anhängen → schreiben {#lesen-filtern-nur-eigenen-entry-entfernen-eigenen-entry-anhaengen-schreiben}
doc = json.loads(STORAGE.read_text())
entries = doc["data"]["entries"]
entries = [e for e in entries if e.get("entry_id") != ENTRY_ID]  # ← nur eigenen!
entries.append(entry)
doc["data"]["entries"] = entries
STORAGE.write_text(json.dumps(doc, indent=2) + "\n")
```

**Kritisch:** Nur nach `entry_id` filtern, nicht nach `domain`. Ein zu breiter Filter (`and e.get("domain") != "mqtt"`) entfernt alle Einträge dieser Domain — also auch solche anderer Integrationen.

### Service-Reihenfolge {#reihenfolge}

```text
q958-secrets-provision (Plaintext + Hashes schreiben)
  ↓ after/wants
home-assistant-mqtt-provision (MQTT-Entry in .storage schreiben)
  ↓ after/wants
home-assistant-smlight-provision (SMLIGHT-Entry in .storage schreiben)
  ↓ before
home-assistant (HA startet erst wenn alle Einträge gesetzt)
```

In Nix:

```nix
systemd.services.home-assistant-smlight-provision = {
  after = [ "home-assistant-mqtt-provision.service" ];
  wants = [ "home-assistant-mqtt-provision.service" ];
  before = [ "home-assistant.service" ];
  wantedBy = [ "multi-user.target" ];
};
```bash

### Was passiert wenn zwei Provision-Services gleichzeitig laufen {#race-condition}

Szenario ohne explizite Reihenfolge (Start ~gleichzeitig, Sekunde 0):

```
t=0: MQTT-Provision startet, liest .storage (enthält alten MQTT-Eintrag mit Blob)
t=0: SMLIGHT-Provision startet, liest .storage (enthält alten MQTT-Eintrag mit Blob)
t=1: MQTT-Provision schreibt .storage mit korrektem Passwort (#1Baumeister)
t=1: SMLIGHT-Provision schreibt .storage mit IHREM gelesen Stand (enthält noch Blob!)
```bash

Ergebnis: MQTT-Eintrag hat wieder die alte Blob, obwohl MQTT-Provision korrekt war. Der letzte Schreiber gewinnt und überschreibt den korrekten Zustand.

## Diagnose {#diagnose}

**Symptom:** MQTT-Provision hat `active (exited)`, aber HA kann sich trotzdem nicht verbinden. SMLIGHT-Provision lief zur selben Zeit.

```bash
# Zeitstempel beider Provision-Services vergleichen: {#zeitstempel-beider-provision-services-vergleichen}
systemctl show home-assistant-mqtt-provision home-assistant-smlight-provision \
  -p ExecMainStartTimestamp --value
# Wenn beide denselben Zeitstempel haben: Race Condition verdächtig {#wenn-beide-denselben-zeitstempel-haben-race-condition-verdaechtig}

# Prüfen ob SMLIGHT-Provision nach MQTT-Provision konfiguriert ist: {#pruefen-ob-smlight-provision-nach-mqtt-provision-konfiguriert-ist}
sudo systemctl cat home-assistant-smlight-provision.service | grep -E "After|Wants"
# Muss enthalten: After=home-assistant-mqtt-provision.service {#muss-enthalten-afterhome-assistant-mqtt-provisionservice}
```

```bash
# Filterfehler erkennen (fehlende Einträge anderer Domains): {#filterfehler-erkennen-fehlende-eintraege-anderer-domains}
sudo python3 -c "
import json, sys
doc = json.load(open('/var/lib/hass/.storage/core.config_entries'))
for e in doc['data']['entries']:
    print(e['domain'], e['entry_id'])
"
# Alle bekannten Integrationen sollten erscheinen {#alle-bekannten-integrationen-sollten-erscheinen}
```bash

<details>
<summary>Vollständige Diagnose</summary>

```bash
# Alle Journal-Einträge beider Provision-Services: {#alle-journal-eintraege-beider-provision-services}
sudo journalctl -u home-assistant-mqtt-provision -u home-assistant-smlight-provision \
  --no-pager -n 50

# .storage Inhalt vollständig ansehen: {#storage-inhalt-vollstaendig-ansehen}
sudo cat /var/lib/hass/.storage/core.config_entries | python3 -m json.tool | grep -E '"domain"|"entry_id"|"password"'

# HA-Fehlerlog: {#ha-fehlerlog}
sudo journalctl -u home-assistant -n 50 --no-pager | grep -iE "error|mqtt|not authorized"
```

</details>

## Fix {#fix}

```bash
# 1. Provision-Services explizit nacheinander erzwingen: {#1-provision-services-explizit-nacheinander-erzwingen}
sudo systemctl stop home-assistant home-assistant-mqtt-provision home-assistant-smlight-provision

sudo systemctl start home-assistant-mqtt-provision
sudo systemctl start home-assistant-smlight-provision
sudo systemctl start home-assistant

# 2. Korrekte Reihenfolge in home-assistant.nix konfigurieren (dann nixos-rebuild switch) {#2-korrekte-reihenfolge-in-home-assistantnix-konfigurieren-dann-nixos-rebuild-switch}
# 3. Verifikation: beide Services haben nach HA-Start active (exited) {#3-verifikation-beide-services-haben-nach-ha-start-active-exited}
systemctl is-active home-assistant-mqtt-provision home-assistant-smlight-provision
```bash

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Deterministischer Zustand nach jedem Rebuild: `.storage` enthält immer die Nix-definierten Einträge
- Neue Integrationen können einfach als weiterer Oneshot-Service hinzugefügt werden
- HA startet erst wenn alle Provision-Services abgeschlossen sind

### Negativ / Trade-offs {#negativ}

- Provision-Services laufen sequenziell — leichte Verlängerung der Bootzeit (in der Praxis < 5s)
- Jede neue Integration braucht einen eigenen Provision-Service mit expliziten `after/wants/before`
- `.storage` wird bei jedem Rebuild neu geschrieben — HA-interne Zustandsänderungen an bekannten Entries (z.B. gespeicherte Passwort-Rotationen) werden überschrieben

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Provision-Services | `modules/70-home-automation/home-assistant.nix` |
| Sequenz-Kette | `after/wants/before` in den Service-Definitionen |

### Verifikation {#verifikation}

```bash
# Beide Provision-Services sind abgeschlossen bevor HA startet: {#beide-provision-services-sind-abgeschlossen-bevor-ha-startet}
sudo systemctl show home-assistant.service -p After --value | grep -E "mqtt-provision|smlight-provision"

# .storage enthält korrekte Einträge nach Rebuild: {#storage-enthaelt-korrekte-eintraege-nach-rebuild}
sudo grep -E '"entry_id"|"password"' /var/lib/hass/.storage/core.config_entries
```

## Alternativen verworfen {#alternativen}

- **Einzelner kombinierter Provision-Service** — ein Script schreibt alle Entries auf einmal, kein Race. Abgelehnt: schlechte Separation of Concerns, jede Integration müsste das Gesamt-Script kennen.
- **HA-Automations-API** — Einträge via REST-API in HA erstellen statt direkt in `.storage` schreiben. HA muss dafür laufen, erfordert Auth-Token, komplexer. Abgelehnt.
- **`configuration.yaml` statt `.storage`** — für MQTT in neueren HA-Versionen nicht mehr unterstützt, HA ignoriert broker/port in `configuration.yaml` ab ≥2026. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-09 | Initial — Race Condition und Filterfehler dokumentiert und gefixt |

## Siehe auch {#siehe-auch}

- [ADR-7001 — LoadCredentialEncrypted](7001-loadcredentialencrypted-vs-loadcredential.md) — Secrets-Handling im Provision-Script
- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — Credentials-Architektur
