---
meta:
  role: adr
  purpose: "Scope-Cut: deklarative *arr-Provisionierung (56-arr-sync) wird nicht auf grapefruitMedia.* portiert -- Recyclarr uebernimmt Quality-Profile"
  status: accepted
  date: 2026-07-15
  error_pattern: ""
  quick_fix: ""
  services: []
  betrifft:
    - modules/50-media/default.nix
    - machines/q958/rollout.nix
  docs:
    - docs/adr/5030-media-stack-factory-hardening.md
    - docs/adr/5033-systemd-socket-on-demand.md
    - modules/50-media/claude-review.md
  tags:
    - adr
    - media
    - provisioning
    - scope-cut
---

# ADR-5034: Scope-Cut -- deklarative *arr-Provisionierung {#adr-5034}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-15 |
| **Host** | q958 |

---

## Kontext {#kontext}

- Der alte 50-media-Stand enthielt 9 Dateien (`56-arr-sync/`, ~1000 Zeilen) fuer
  deklarative Bootstrap-Provisionierung: Download-Clients, Indexer, API-Key-Sync,
  Jellyfin-Admin, Jellyseerr-Bootstrap, Locale, Quality-Profile, Repack-Settings.
- Beim 50-media-Rewrite (2026-07-15) wurden diese Dateien ersatzlos entfernt
  (Review-Finding H1, `claude-review.md`).
- Quality-Profile und Custom-Formats werden ab sofort von **Recyclarr via Trash Guides**
  synchronisiert (`560-recyclarr/default.nix`). Das ist die Standard-Methode
  in der *arr-Community -- deklarativer, versionierter, community-gepflegt.
- Die verbleibenden Provisionierungs-Aufgaben (Download-Clients, Indexer-Sync,
  Jellyfin-Admin, Jellyseerr-Bootstrap) werden **einmalig manuell** im UI
  konfiguriert. Sie aendern sich selten; deklarativer Aufwand uebersteigt Nutzen.
- `packages/arr-provision` (Go-Binary, Grundlage der alten `56-arr-sync`) existiert
  im Repo nicht mehr.

## Entscheidung {#entscheidung}

**56-arr-sync wird nicht auf `grapefruitMedia.*` portiert. Recyclarr uebernimmt
Quality-Profile; restliche Erstkonfiguration erfolgt manuell im UI.**

### Recyclarr -- Quality-Profile und Custom Formats {#recyclarr}

Recyclarr (`modules/50-media/560-recyclarr/default.nix`) synct vollautomatisch:

- TRaSH-Guide Custom Formats (CFs) fuer Sonarr + Radarr
- Quality-Profile "German 1080p HEVC" + "English 1080p HEVC"
- Score-Systematik (10000er-Sprachgates, Repack-Priorisierung)

```nix
grapefruitMedia.recyclarr.enable = true;  # rollout Stufe 6
```

### Manuelle Erstkonfiguration (einmalig nach Fresh-Deploy) {#manuell}

Nach dem ersten `nixos-rebuild switch` im UI konfigurieren:

1. **SABnzbd** (`http://localhost:5007`): Usenet-Provider-Credentials eintragen
2. **Prowlarr** (`http://localhost:5006`): TreasureMaps-Indexer hinzufuegen
   (API-Key aus `/var/lib/secrets/treasuremaps_api_key`)
3. **Sonarr/Radarr** (`localhost:5003/5004`): Download-Client = SABnzbd,
   Root-Folder, Prowlarr als Indexer-Sync-App
4. **Jellyseerr** (`localhost:5002`): Jellyfin + Sonarr/Radarr verknuepfen
5. **Lidarr/Readarr** (on-demand): analog

### TreasureMaps-Konfiguration (aus rollout.nix aufbewahrt) {#treasuremaps}

```
# TreasureMaps-Indexer fuer Prowlarr (manuell eintragen):
Name:       TreasureMaps
Base URL:   https://treasure-maps.com
API Key:    /var/lib/secrets/treasuremaps_api_key

Backup-Indexer:
Name:       TreasureMaps (Backup)
Base URL:   https://treasure-maps.com
API Key:    /var/lib/secrets/treasuremaps_api_key
Categories: 5000 5100 5140 2000 2100 2140
Apps:       sonarr radarr
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Recyclarr ist battle-tested, community-gepflegt und deckt Quality-Profile besser
  ab als eigener Code.
- Kein toter Code im Repo (56-arr-sync wuerde sonst nie getestet werden).
- `grapefruitMedia.*`-Modul bleibt schlanker und portabler.
- Fresh-Deploy-Zeit reduziert sich (kein komplexer Provisionierungs-Service).

### Negativ / Trade-offs {#negativ}

- Fresh-Deploy erfordert manuelle UI-Konfiguration (~15 min).
- Keine idempotente Automatisierung wenn API-Keys rotieren (Recyclarr-Reconnect
  passiert automatisch, Prowlarr/Seerr-Reconnect manuell).
- Jellyfin-Admin-Bootstrap nicht deklarativ.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Scope-Cut ADR | `docs/adr/5034-scope-cut-arr-provision.md` |
| rollout.nix TODO entfernt | `machines/q958/rollout.nix` |
| TreasureMaps-Konfig aufbewahrt | (in diesem ADR, Abschnitt #treasuremaps) |

## Alternativen verworfen {#alternativen}

- **arr-provision portieren**: Haette ~1000 Zeilen Go + Nix bedeutet, die
  ausschliesslich Fresh-Deploy-Faelle abdecken. Kosten > Nutzen. Abgelehnt.
- **sops-nix + Ansible**: Infrastruktur-Overkill fuer ein Single-Node-Homelab.
  Abgelehnt.

## Changelog {#changelog}

| Datum | Aenderung |
|-------|-----------|
| 2026-07-15 | Initial (50-media-Review Block 6) |

## Siehe auch {#siehe-auch}

- [ADR-5030 -- Media Stack Factory Hardening](5030-media-stack-factory-hardening.md) -- Sicherheits-Kontext
- [ADR-5033 -- Systemd Socket On-Demand](5033-systemd-socket-on-demand.md) -- On-Demand-Konzept
- [claude-review.md H1](../../../modules/50-media/claude-review.md) -- Original-Finding

---

> **Markdown-Referenz:** [CLAUDE-GUIDE.md](CLAUDE-GUIDE.md)
