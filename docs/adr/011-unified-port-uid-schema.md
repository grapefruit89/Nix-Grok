---
meta:
  role: doc
  purpose: ADR-011 Unified Port=UID=FolderPrefix Schema (4-stellig)
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-server-map.md
    - docs/adr/004-unix-socket-upstreams.md
    - docs/adr/008-nftables-l4-hardening.md
  lib:
    - lib/uid-registry.nix
    - lib/unix-sockets.nix
    - lib/server-map.nix
    - modules/00-core/01-core.nix
  tags:
    - adr
    - uid
    - ports
    - server-map
---

# ADR-011: Unified Port = UID = FolderPrefix Schema (4-stellig)

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-27 |
| **Host** | q958 |
| **Rollout** | Stufe 6 (alle Services) |

## Kontext

- Ports waren historisch gewachsen: 8989 (Sonarr), 7878 (Radarr), 28981 (Paperless) — kein System.
- UIDs für *arr-Services: 969/978/984/987/989 — zufällig, kein Bezug zum Modul.
- nftables `skuid`-Regeln brauchen statische, merkbare UIDs (ADR-008).
- KI-Assistenten müssen Port ↔ UID ↔ Modul in einem Schritt ableiten können.

## Entscheidung

**Eine Regel: ID = Port = UID = Ordner-Präfix (4-stellig)**

| Ordner | Präfix | Beispiele |
|--------|--------|-----------|
| `10-network` | `10xx` | pocket-id=1001, technitium=1002, ddns=1003, zigbee=1004 |
| `40-observability` | `40xx` | grafana=4001, loki=4002, gatus=4003, crowdsec=4004, scrutiny=4005 |
| `50-media` | `50xx` | jellyfin=5001, sonarr=5003, radarr=5004, readarr=5005, prowlarr=5006, sabnzbd=5007 |
| `60-apps` | `60xx` | vaultwarden=6001, homepage=6002, paperless=6003, linkwarden=6006, open-webui=6007 |
| `70-forge` | `70xx` | forgejo=7001, semaphore=7002, cockpit=7003, amp=7004 |

### Ausnahmen (unveränderlich)
- **SSH = 22**, **DNS = 53**, **MQTT = 1883** — IANA-Standards, externe Geräte
- **Valkey = 6379** — RESP2-Protokoll-Default, nutzt UDS ohnehin

### Single Source of Truth

| Artefakt | Quelle |
|----------|--------|
| Port-Defaults | `modules/00-core/01-core.nix` → `my.ports.*` |
| UID/GID | `lib/uid-registry.nix` → `defaultUsers` / `defaultGroups` |
| UDS-Pfade | `lib/unix-sockets.nix` |
| Server-Landkarte | `lib/server-map.nix` (Dokumentation, kein Config-Input) |

## Konsequenzen

### Positiv

- KI kann Port, UID und Modul ohne Suche ableiten: `sonarr` → 5003.
- nftables `skuid 5006 accept` ist selbsterklärend: Prowlarr darf VPN nutzen.
- Neue Services: Ordner-Präfix nehmen, nächste freie Stelle belegen.
- Server-Map (`lib/server-map.nix`) ist maschinenlesbare Dokumentation.

### Negativ

- Einmalige UID-Migration: `chown -R` auf `/persist/var/lib/{sonarr,...}` nötig.
- Port-Änderungen erfordern Firewall-/Caddy-Reload (kein Hard-Blackout).
- Unix Sockets für *arr (Servarr/.NET) nicht möglich — bleiben TCP.

### Unix Socket Ausbau (via ADR-004)

| Transport | Services |
|-----------|---------|
| **UDS (aktiv)** | forgejo, grafana, valkey |
| **UDS (neu)** | pocket-id, gatus, vaultwarden, paperless, linkwarden, open-webui, homepage, semaphore |
| **TCP (bleibt)** | jellyfin, sonarr, radarr, readarr, prowlarr, sabnzbd, audiobookshelf, jellyseerr, n8n, filebrowser, loki, crowdsec, scrutiny, cockpit, amp |
| **Extern** | SSH, DNS, MQTT, Tailscale |

## Implementierung

```
lib/uid-registry.nix        ← UIDs 5003–5007 (*arr)
lib/unix-sockets.nix        ← 11 UDS-Pfade
lib/server-map.nix          ← Server-Landkarte (Doku)
modules/00-core/01-core.nix ← Port-Defaults auf 4-stellig
scripts/migrate-arr-uids.sh ← Einmalige chown-Migration
```

## Migration *arr UIDs

Einmalig nach `nixos-rebuild switch`:
```bash
sudo /etc/nixos/scripts/migrate-arr-uids.sh
```

Ändert UID/GID auf `/persist/var/lib/{sonarr,radarr,readarr,prowlarr,sabnzbd}`.

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-06-27 | Initial — KB-Mitnahme, Port/UID-Unification implementiert |
