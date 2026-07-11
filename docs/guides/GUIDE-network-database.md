---
meta:
  role: doc
  purpose: Betriebsguide DNS (Blocky), Valkey, PostgreSQL
  date: 2026-07-10
  status: current
  docs:
    - docs/adr/1001-dns-dot-fail-closed.md
    - docs/adr/1004-unix-socket-upstreams.md
    - docs/adr/011-unified-port-uid-schema.md
    - docs/adr/1002-ipv6-homelab-v4-only.md
    - modules/10-network/default.nix
  tags:
    - network
    - blocky
    - postgresql
---

# Network & Database Guide {#guide-network-database}

> Blocky als LAN-DNS, Valkey-Cache und PostgreSQL auf Tier A — Pfade und Diagnose für q958.

## Architektur {#architektur}

| Dienst | Rolle | Persistenz |
|--------|-------|------------|
| Blocky | DoT-Upstreams, lokale Records | `/var/lib/blocky` (Tier A) |
| Valkey | LRU-Cache (Paperless, n8n, …) | RAM, Port aus `my.ports.valkey` |
| PostgreSQL | Transaktionale DBs | `/var/lib/postgresql` (Tier A) |

Konfiguration: `machines/q958/default.nix` → `my.configs`; Aktivierung: `machines/q958/rollout.nix` (ab Stufe 2).

Valkey und PostgreSQL kommunizieren intern über Unix Domain Sockets ([ADR-1004](../adr/1004-unix-socket-upstreams.md)).

## PostgreSQL {#postgresql}

```bash
systemctl status postgresql.service
sudo -u postgres psql -c "\l+"
```text

Backup-Dump auf persistentem Tier A (nicht mergerfs):

```bash
sudo -u postgres pg_dumpall > /persist/var/lib/postgresql/pg_backup_$(date +%F).sql
```

OOM-Schutz: PostgreSQL `shared_buffers` ~8G — MemoryMax skaliert mit `hardware.ramGB` ([ADR-003](../adr/003-oom-cgroup-isolation.md#tier-modell)).

## Valkey {#valkey}

```bash
sudo -u valkey valkey-cli info memory
```bash

Valkey nutzt UDS `/run/redis-valkey/valkey.sock` — kein TCP-Port ([ADR-1004](../adr/1004-unix-socket-upstreams.md)).

## Blocky {#blocky}

- Upstreams: `machines/q958/profile.nix` → `network.blocky.upstream`
- Denylists / Client-Groups: `modules/10-network/default.nix`
- LAN-Clients: DNS = Host-IP (`192.168.2.73`), Port 53

```bash
dig @127.0.0.1 cloudflare.com +short
systemctl status blocky.service
```

Blocky ist Tier-0-Dienst mit MemoryMax 500M und OOMScoreAdjust −900 ([ADR-1001](../adr/1001-dns-dot-fail-closed.md), [ADR-003](../adr/003-oom-cgroup-isolation.md)).

## Siehe auch {#siehe-auch}

- [ADR-1001 — DNS-over-TLS fail-closed](../adr/1001-dns-dot-fail-closed.md) — Blocky als Tier-0-Dienst
- [ADR-1002 — IPv6 v4-only](../adr/1002-ipv6-homelab-v4-only.md) — warum nur IPv4 im Homelab
- [ADR-1004 — Unix-Socket-Upstreams](../adr/1004-unix-socket-upstreams.md) — Valkey und PostgreSQL via UDS
- [ADR-011 — Port=UID-Schema](../adr/011-unified-port-uid-schema.md) — Port-Konvention für 10xx-Services
- [ADR-003 — OOM-Isolation](../adr/003-oom-cgroup-isolation.md) — MemoryMax für PostgreSQL und Blocky
