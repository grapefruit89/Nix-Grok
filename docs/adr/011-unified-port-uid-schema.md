---
meta:
  role: doc
  purpose: ADR-011 Unified Port=UID=FolderPrefix Schema (4-stellig) — deterministisch, KI-ableitbar
  status: accepted
  date: 2026-06-27
  betrifft:
    - lib/uid-registry.nix
    - lib/unix-sockets.nix
    - lib/server-map.nix
    - modules/00-core/01-core.nix
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-server-map.md
    - docs/adr/004-unix-socket-upstreams.md
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/008-nftables-l4-hardening.md
    - docs/adr/012-modern-cli-tools.md
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
    - nftables
---

# ADR-011: Unified Port = UID = FolderPrefix Schema (4-stellig) {#adr-011}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-27 |
| **Host** | q958 |
| **Rollout** | Stufe 6 (alle Services) |

## Kontext {#kontext}

- Ports waren historisch gewachsen: 8989 (Sonarr), 7878 (Radarr), 28981 (Paperless) — kein System, KI-Lookup nötig.
- UIDs für *arr-Services: 969/978/984/987/989 — zufällig, kein Bezug zum Modul.
- nftables `skuid`-Regeln brauchen statische, merkbare UIDs ([ADR-008](008-nftables-l4-hardening.md) — `skuid`-basierte VPN-Freigabe pro App).
- KI-Assistenten müssen Port ↔ UID ↔ Modul in einem Schritt ableiten können — ohne Lookup in Konfigurationsdateien.
- Das dendritische Modul-Layout ([ADR-007](007-dendritic-one-file-per-service.md)) macht den Ordner-Präfix (`50-media`, `60-apps`, …) zur natürlichen Basis.
- Unix-Socket-Upstreams ([ADR-004](004-unix-socket-upstreams.md)) brauchen eindeutige UDS-Pfade je Dienst.

## Entscheidung {#entscheidung}

**Eine Regel: ID = Port = UID = Ordner-Präfix (4-stellig)**

| Ordner | Präfix | Beispiele |
|--------|--------|-----------|
| `10-network` | `10xx` | pocket-id=1001, technitium=1002, ddns=1003, zigbee=1004 |
| `40-observability` | `40xx` | grafana=4001, loki=4002, gatus=4003, crowdsec=4004, scrutiny=4005 |
| `50-media` | `50xx` | jellyfin=5001, sonarr=5003, radarr=5004, readarr=5005, prowlarr=5006, sabnzbd=5007 |
| `60-apps` | `60xx` | vaultwarden=6001, homepage=6002, paperless=6003, linkwarden=6006, open-webui=6007 |
| `70-forge` | `70xx` | forgejo=7001, semaphore=7002, cockpit=7003, amp=7004 |

### Ausnahmen (unveränderlich) {#ausnahmen}

- **SSH = 22**, **DNS = 53**, **MQTT = 1883** — IANA-Standards, externe Geräte können nicht umgestellt werden.
- **Valkey = 6379** — RESP2-Protokoll-Default, nutzt UDS ohnehin ([ADR-004](004-unix-socket-upstreams.md)).

### Single Source of Truth {#single-source}

| Artefakt | Quelle | Zweck |
|----------|--------|-------|
| Port-Defaults | `modules/00-core/01-core.nix` → `my.ports.*` | NixOS-Options, Module greifen darauf zu |
| UID/GID | `lib/uid-registry.nix` → `defaultUsers` / `defaultGroups` | Statische UIDs für nftables + Filesystem |
| UDS-Pfade | `lib/unix-sockets.nix` | Socket-Pfade für Caddy-Upstreams |
| Server-Landkarte | `lib/server-map.nix` | Maschinenlesbare Doku (kein Config-Input) |

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- KI kann Port, UID und Modul ohne Suche ableiten: `sonarr` → 5003, Modul `50-media`, nftables `skuid 5003`.
- nftables `skuid 5006 accept` ist selbsterklärend: Prowlarr darf VPN nutzen ([ADR-008](008-nftables-l4-hardening.md)).
- Neue Services: Ordner-Präfix nehmen, nächste freie Stelle belegen — kein Koordinationsaufwand.
- `lib/server-map.nix` ist maschinenlesbare Dokumentation für Grafana/Dashboards.

### Negativ {#negativ}

- Einmalige UID-Migration: `chown -R` auf `/persist/var/lib/{sonarr,...}` nötig → [Migration](#migration).
- Port-Änderungen erfordern Firewall-/Caddy-Reload (kein Hard-Blackout, aber kurze Unterbrechung).
- Unix Sockets für *arr (Servarr/.NET) nicht möglich — bleiben TCP (→ [ADR-004](004-unix-socket-upstreams.md#konsequenzen)).

### Unix Socket Ausbau {#unix-sockets}

Vollständige Entscheidung welche Dienste UDS nutzen: [ADR-004](004-unix-socket-upstreams.md)

| Transport | Services |
|-----------|---------|
| **UDS (aktiv)** | forgejo, grafana, valkey |
| **UDS (neu)** | pocket-id, gatus, vaultwarden, paperless, linkwarden, open-webui, homepage, semaphore |
| **TCP (bleibt)** | jellyfin, sonarr, radarr, readarr, prowlarr, sabnzbd, audiobookshelf, jellyseerr, loki, crowdsec, scrutiny, cockpit |
| **Extern** | SSH (22), DNS (53), MQTT (1883), Tailscale |

## Implementierung {#implementierung}

```
lib/uid-registry.nix        ← UIDs 5003–5007 (*arr), alle anderen Services
lib/unix-sockets.nix        ← 11 UDS-Pfade (Caddy-Upstreams)
lib/server-map.nix          ← Server-Landkarte (Doku, kein Config-Input)
modules/00-core/01-core.nix ← Port-Defaults 4-stellig als NixOS-Options
scripts/migrate-arr-uids.sh ← Einmalige chown-Migration
```

## Migration *arr UIDs {#migration}

Einmalig nach `nixos-rebuild switch` (UID-Änderung braucht neue Prozesse):

```bash
sudo /etc/nixos/scripts/migrate-arr-uids.sh
```

Ändert UID/GID auf `/persist/var/lib/{sonarr,radarr,readarr,prowlarr,sabnzbd}`.

## Alternativen verworfen {#alternativen}

- **Beliebige Port-Verteilung (historisch gewachsen)** — nicht deterministisch, KI braucht Lookup in Config; erzeugt Fehler bei nftables-Rules die UIDs referenzieren. Abgelehnt.
- **16-bit UIDs (Linux-Defaults, 1000+)** — kein Bezug zu Port/Modul, Kollisionen mit nixpkgs-generierten UIDs möglich. Abgelehnt.
- **Nur UDS, kein TCP** — .NET-Runtime (Servarr-Apps) unterstützt kein Unix-Socket-Listening. Faktisch nicht umsetzbar.
- **Port-Namespace je Modul getrennt** — zu wenig Präzedenz (max. 99 Services pro Modul), reicht für Homelab; vereinfacht Ableitungsregel.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-06-27 | Initial — KB-Mitnahme, Port/UID-Unification implementiert |

## Siehe auch {#siehe-auch}

- [ADR-007 — Dendritische Module](007-dendritic-one-file-per-service.md) — Ordner-Struktur als Basis für Präfix-Schema
- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — `skuid`-Regeln die statische UIDs aus diesem Schema nutzen
- [ADR-004 — Unix-Socket-Upstreams](004-unix-socket-upstreams.md) — welche Dienste UDS statt TCP nutzen
- [ADR-012 — Moderne CLI-Tools](012-modern-cli-tools.md) — gleicher DX-Commit-Kontext (Stufe 6)
