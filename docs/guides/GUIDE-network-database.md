---
meta:
  role: doc
  purpose: Betriebsguide DNS (Blocky), Valkey, PostgreSQL
  docs:
    - docs/adr/001-dns-dot-fail-closed.md
    - modules/10-network.nix
  tags:
    - network
    - blocky
    - postgresql
---

# Network & Database Guide

> Blocky als LAN-DNS, Valkey-Cache und PostgreSQL auf Tier A — Pfade und Diagnose für q958.

## Architektur

| Dienst | Rolle | Persistenz |
|--------|-------|------------|
| Blocky | DoT-Upstreams, lokale Records | `/var/lib/blocky` (Tier A) |
| Valkey | LRU-Cache (Paperless, n8n, …) | RAM, Port aus `my.ports.valkey` |
| PostgreSQL | Transaktionale DBs | `/var/lib/postgresql` (Tier A) |

Konfiguration: `machines/q958/default.nix` → `my.configs`; Aktivierung: `machines/q958/rollout.nix` (ab Stufe 2).

## PostgreSQL

```bash
systemctl status postgresql.service
sudo -u postgres psql -c "\l+"
```

Backup-Dump auf persistentem Tier A (nicht mergerfs):

```bash
sudo -u postgres pg_dumpall > /persist/var/lib/postgresql/pg_backup_$(date +%F).sql
```

## Valkey

```bash
sudo -u valkey valkey-cli info memory
```

## Blocky

- Upstreams: `machines/q958/profile.nix` → `network.blocky.upstream`
- Denylists / Client-Groups: `modules/10-network.nix`
- LAN-Clients: DNS = Host-IP (`192.168.2.73`), Port 53

```bash
dig @127.0.0.1 cloudflare.com +short
systemctl status blocky.service
```

## Verwandte ADRs

- [001 DNS fail-closed](../adr/001-dns-dot-fail-closed.md)
- [002 IPv6 v4-only](../adr/002-ipv6-homelab-v4-only.md)