---
meta:
  role: doc
  purpose: ADR-004 Unix-Socket-Upstreams für Caddy — weniger TCP-Ports, klarere Ingress-Grenze
  status: accepted
  date: 2026-06-17
  betrifft:
    - lib/unix-sockets.nix
    - lib/caddy-helpers.nix
    - lib/service-factory.nix
  docs:
    - docs/adr/README.md
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/011-unified-port-uid-schema.md
  tags:
    - adr
    - caddy
    - unix-sockets
    - uds
---

# ADR-004: Unix-Socket-Upstreams für interne Dienste {#adr-004}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext {#kontext}

- TCP-Ports auf `127.0.0.1` sind einfach, aber jeder Dienst braucht eine Port-Nummer und `ss`-Sichtbarkeit.
- Valkey, Forgejo und Grafana sollen ohne zusätzliche TCP-Listener an Caddy angebunden werden.
- Pfade müssen zentral dokumentiert sein, damit Module nicht eigene Socket-Pfade erfinden.
- Port-/UID-Schema ([ADR-011](011-unified-port-uid-schema.md)) legt fest welche Dienste UDS statt TCP nutzen.
- Dienst-Dateien folgen dem dendritischen Layout ([ADR-007](007-dendritic-one-file-per-service.md)) — jede Datei registriert ihren Socket in `lib/unix-sockets.nix`.

## Entscheidung {#entscheidung}

1. **Eine Wahrheit:** `lib/unix-sockets.nix` — Pfade + `toCaddyUpstream`.
2. **Caddy-Helfer:** `lib/caddy-helpers.nix` → `proxyUnixSso`, `proxyUnixDirect`, …
3. **Kein Socket** ohne Eintrag in `unix-sockets.nix` — neue Dienste erweitern die Lib zuerst.

### TCP-Ausnahmen {#tcp-ausnahmen}

Dienste die **nicht** auf UDS wechseln können:

| Dienst | Grund |
|--------|-------|
| Jellyfin, *arr, SABnzbd | .NET-Runtime (Servarr) unterstützt kein Unix-Socket-Listening |
| Loki, CrowdSec, Scrutiny | Externe Clients erwarten TCP |
| SSH, DNS, MQTT | IANA-Standards |

Vollständige UDS-vs-TCP-Liste: [ADR-011](011-unified-port-uid-schema.md#unix-sockets)

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Weniger Port-Kollisionen; klarere Grenze Ingress ↔ App.
- `mkService` in `service-factory.nix` unterstützt `socketPath` als Alternative zu `port`.

### Negativ {#negativ}

- Socket-Berechtigungen (Gruppe `caddy`, `redis`) müssen pro Dienst stimmen.
- Debugging mit `curl` schwieriger als bei TCP — `socat` oder Unit-Logs nutzen.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Socket-SSOT | `lib/unix-sockets.nix` |
| Caddy-Helfer | `lib/caddy-helpers.nix` |
| Registry | `NIXH-05-LIB-005` in `docs/SPEC_REGISTRY.md` |

## Alternativen verworfen {#alternativen}

- **Alle Dienste auf TCP belassen** — Port-Kollisionen, `ss`-Übersicht unübersichtlich. Abgelehnt.
- **Socket-Pfade pro Modul selbst definieren** — keine zentrale Dokumentation, Pfad-Konflikte möglich. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-007 — Dendritische Module](007-dendritic-one-file-per-service.md) — Modulstruktur in der Sockets definiert werden
- [ADR-011 — Port/UID-Schema](011-unified-port-uid-schema.md#unix-sockets) — Entscheidung UDS vs. TCP pro Dienst
- [GUIDE-server-map.md](../guides/GUIDE-server-map.md) — Übersicht aller Services mit UDS vs. TCP Transport
- [GUIDE-network-database.md#valkey](../guides/GUIDE-network-database.md#valkey) — Valkey und PostgreSQL via UDS
