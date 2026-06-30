---
meta:
  role: doc
  purpose: rsync, rclone, restic — NixOS-Risiken und Homelab-Einsatz
  docs:
    - docs/guides/GUIDE-storage-tiers.md
    - docs/adr/002-ipv6-homelab-v4-only.md
    - docs/adr/003-oom-cgroup-isolation.md
    - modules/30-storage.nix
  tags:
    - storage
    - restic
    - rclone
---

# Data Management Guide {#guide-data-management}

> rsync, rclone und restic im q958-Kontext — bekannte Fallstricke.

## rsync {#rsync}

| Risiko | Mitigation |
|--------|------------|
| IPv6 disabled ([ADR-002](../adr/002-ipv6-homelab-v4-only.md)) | Explizit IPv4-Ziele nutzen |
| Colon in IPv6-URIs | `[addr]:/path` Syntax |
| WSL metadata | Nicht relevant auf q958 |

Einsatz: Storage-Mover nutzt **rclone**, nicht rsync ([GUIDE-storage-tiers.md#storage-mover](GUIDE-storage-tiers.md#storage-mover)).

## rclone {#rclone}

| Risiko | Mitigation |
|--------|------------|
| FUSE setuid | nixpkgs-Wrapper → `/run/wrappers/bin/fusermount3` |
| SOPS race at boot | Services `after = [ sops-nix.service ]` (Stufe 9) |
| Journal flood bei `-vv` | Log-Level in Timern begrenzen |

Storage-Mover: `rclone move` von Tier-B-Cache → Tier-C mit `--min-age 30d`.

## restic {#restic}

| Risiko | Mitigation |
|--------|------------|
| DB write drift | `backupPrepareCommand` stoppt PostgreSQL + Apps |
| MediaCover bloat | `exclude` in `30-storage.nix` |
| Netzwerk nicht ready | Timer nach `network-online.target` |

```bash
systemctl status restic-backups-tier-a-sovereign.timer
restic -r s3:... snapshots   # mit env aus /var/lib/secrets/restic_s3_creds
```

## SSoT {#ssot}

Pfade, Timer und Excludes leben in `modules/30-storage.nix`; Geräte/Labels in `machines/q958/profile.nix`.

## Siehe auch {#siehe-auch}

- [GUIDE-storage-tiers.md](GUIDE-storage-tiers.md) — Tier-Policy, Impermanence, MediaCover
- [ADR-002 — IPv6 v4-only](../adr/002-ipv6-homelab-v4-only.md) — warum IPv4-Explizit bei rsync nötig
- [ADR-003 — OOM-Isolation](../adr/003-oom-cgroup-isolation.md) — Restic-Backup stoppt PostgreSQL (MemoryMax-Interaktion)
- [GUIDE-disk-health.md](GUIDE-disk-health.md) — SMART-Monitoring der Tier-C HDDs auf die restic sichert
