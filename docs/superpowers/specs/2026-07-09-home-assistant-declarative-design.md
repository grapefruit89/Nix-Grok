# Design: Home Assistant — Security-Fixes + Maximale Deklarativität

**Datum:** 2026-07-09  
**Status:** Approved — bereit für Implementierung  
**Scope:** `modules/70-home-automation/home-assistant.nix`

---

## Kontext

Der Home-Automation-Layer läuft produktiv (HA, Zigbee2MQTT, Mosquitto alle aktiv).
Keine Zigbee-Geräte bisher gepairt — idealer Zeitpunkt für Architektur-Entscheidungen.

Zwei Probleme wurden im Audit identifiziert:
1. Python-Provisioning-Scripts haben Security-Lücken (Secrets-Fallback, fehlende Fehlerbehandlung)
2. `configuration.yaml` enthält nur Basis-Config aus Nix — `recorder`, `logbook`, `history`,
   Lovelace-Modus und Helper-Entities fehlen

---

## Ziel

- **Sicher:** Provisioning-Scripts schlagen laut fehl statt still zu degradieren
- **Deklarativ:** Alle stabilen HA-Configs in Nix — reproduzierbar und in Git
- **Ergonomisch:** Schnell ändernde Dinge (Automationen, Dashboard-Inhalt) bleiben im HA-UI

---

## Grenzziehung: Nix vs. UI

| Bereich | Verwaltet in | Begründung |
|---------|-------------|------------|
| `homeassistant.*`, `http.*` | Nix ✅ bereits | Systemkonfig, ändert sich nie |
| `recorder`, `logbook`, `history` | **Nix (neu)** | Infrastruktur, stabil |
| `lovelace.mode = "yaml"` | **Nix (neu)** | Einmalige Architektur-Entscheidung |
| Dashboard-Skeleton | **Nix (einmalig)** | `tmpfiles F` — erstellt nur wenn nicht vorhanden |
| Dashboard-Karteninhalt | HA-UI | Ändert sich häufig beim Einrichten |
| Helper-Entities | **Nix (neu, Pattern)** | Infrastruktur für Automationen |
| Automationen, Scripts, Scenes | HA-UI (`.storage`) | Ändern sich mit jedem neuen Gerät |
| MQTT-Integration | Provisioning-Script | HA ≥2026 erzwingt `.storage` JSON |
| SMLIGHT-Integration | Provisioning-Script | HA ≥2026 erzwingt `.storage` JSON |

---

## Teil A — Security-Fixes

### A1: Secrets-Fallback entfernen (beide Scripts)

**Problem:** Wenn `CREDENTIALS_DIRECTORY` nicht gesetzt ist (systemd-creds nicht geladen),
fällt das Script still auf `/var/lib/secrets/` zurück. Das maskiert Konfigurationsfehler.

**Fix in `hassMqttProvision` und `hassSmLightProvision`:**
```python
# Vorher:
_creds = os.environ.get("CREDENTIALS_DIRECTORY", "")
PASSWORD_FILE = Path(_creds) / "..." if _creds else Path("/var/lib/secrets/...")

# Nachher — hartes Exit:
_creds = os.environ.get("CREDENTIALS_DIRECTORY")
if not _creds:
    raise SystemExit("FEHLER: CREDENTIALS_DIRECTORY nicht gesetzt — q958-secrets-provision ausführen")
PASSWORD_FILE = Path(_creds) / "homeassistant_mqtt_password"
```

Gilt nur für `hassMqttProvision` (benötigt Credentials). `hassSmLightProvision` hat keine
Credentials — dort entfällt dieser Fix.

### A2: Fehlerbehandlung bei Datei-Permissions (beide Scripts)

**Problem:** `os.chown()` / `os.chmod()` schlagen lautlos fehl wenn der User nicht existiert
oder Berechtigungen fehlen. HA startet dann mit falschen Permissions.

**Fix:**
```python
# Vorher:
os.chown(STORAGE, uid, gid)
os.chmod(STORAGE, 0o600)
os.chown(STORAGE.parent, uid, gid)

# Nachher:
try:
    os.chown(STORAGE, uid, gid)
    os.chmod(STORAGE, 0o600)
    os.chown(STORAGE.parent, uid, gid)
except OSError as e:
    raise SystemExit(f"FEHLER: Berechtigungen konnten nicht gesetzt werden: {e}")
```

---

## Teil B — Nix-Config erweitern

### B1: `configuration.yaml` Erweiterungen

Zum bestehenden `services.home-assistant.config`-Block hinzufügen:

```nix
lovelace.mode = "yaml";

recorder.purge_keep_days = 30;

logbook = {};

history = {};
```

**Lovelace:** `mode = "yaml"` aktiviert den YAML-Modus. HA erwartet dann `ui-lovelace.yaml`
in `configDir`. Die Datei wird via B2 initial angelegt.

**Recorder:** `purge_keep_days = 30` — explizit statt implizitem Default (10 Tage).
Ausreichend für Debugging, verhindert unbegrenztes DB-Wachstum.

**Logbook + History:** Leere Attrsets aktivieren die Komponenten mit Defaults.
Ohne Eintrag in `configuration.yaml` sind sie in neueren HA-Versionen disabled.

### B2: Dashboard-Skeleton via `systemd.tmpfiles`

`systemd.tmpfiles F` unterstützt keinen Mehrzeilen-Inhalt direkt. Stattdessen:
`pkgs.writeText` erzeugt die Skeleton-Datei im Nix-Store, `tmpfiles C` kopiert sie
einmalig in `configDir` — **nur wenn die Zieldatei noch nicht existiert**.

```nix
let
  dashboardSkeleton = pkgs.writeText "ui-lovelace.yaml" ''
    views:
      - title: Home
        path: home
        icon: mdi:home
        cards: []
  '';
in
# In config-Block:
systemd.tmpfiles.rules = [
  # 'C' = kopiere Quelle nach Ziel, NUR wenn Ziel nicht existiert — überschreibt nie
  "C ${cfg.stateDir}/ui-lovelace.yaml 0640 ${cfg.user} ${cfg.group} - ${dashboardSkeleton}"
];
```

**Wichtig:** Typ `C` (nicht `L`) — die Datei wird einmalig kopiert und gehört dem User.
Bei `nixos-rebuild switch` wird sie **nicht** überschrieben. Der HA-YAML-Editor kann
sie frei bearbeiten.

### B3: Helper-Entities Option (Pattern, initial leer)

Neue Option in `options.my.services.home-assistant`:

```nix
helperEntities = lib.mkOption {
  type = lib.types.attrs;
  default = {};
  description = ''
    HA Helper-Entities als Nix-Attrset — wird zu configuration.yaml zusammengeführt.
    Beispiel: { input_boolean.guest_mode = { name = "Gäste-Modus"; }; }
  '';
};
```

In der `config`-Section wird das Attrset in den `services.home-assistant.config`-Block
gemergt: `// cfg.helperEntities`. So können Helper-Entities deklarativ in `profile.nix`
definiert werden ohne `home-assistant.nix` zu ändern.

---

## Nicht im Scope

- Automationen in Nix (Rebuild-Overhead zu hoch im Alltag)
- Dashboard-Karteninhalt in Nix (zu viel Tinkering)
- Observability / SLZB-Health-Monitoring
- SMLIGHT/MQTT-Provisioning-Architektur (bleibt wie es ist)

---

## Verifikation

```bash
# 1. Dry-Build muss clean durchlaufen:
sudo nixos-rebuild dry-build --flake /etc/nixos#q958 --impure

# 2. Nach switch: configuration.yaml prüfen:
sudo cat /var/lib/hass/configuration.yaml | grep -E "lovelace|recorder|logbook|history"

# 3. Dashboard-Skeleton vorhanden:
sudo ls -la /var/lib/hass/ui-lovelace.yaml

# 4. Provisioning-Services erfolgreich:
systemctl status home-assistant-mqtt-provision home-assistant-smlight-provision

# 5. HA erreichbar und kein Fehler im Log:
sudo journalctl -u home-assistant --since "5 minutes ago" | grep -i error
```
