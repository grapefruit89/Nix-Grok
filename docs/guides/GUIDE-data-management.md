---
meta:
  role: doc
  purpose: rsync, rclone, restic — NixOS-Risiken und Homelab-Einsatz
  docs:
    - docs/guides/GUIDE-storage-tiers.md
    - modules/30-storage.nix
  tags:
    - storage
    - restic
    - rclone
---

# Data Management Guide

> rsync, rclone und restic im q958-Kontext — bekannte Fallstricke.

## rsync

| Risiko | Mitigation |
|--------|------------|
| IPv6 disabled (ADR-002) | Explizit IPv4-Ziele nutzen |
| Colon in IPv6-URIs | `[addr]:/path` Syntax |
| WSL metadata | Nicht relevant auf q958 |

Einsatz: Storage-Mover nutzt **rclone**, nicht rsync.

## rclone

| Risiko | Mitigation |
|--------|------------|
| FUSE setuid | nixpkgs-Wrapper → `/run/wrappers/bin/fusermount3` |
| SOPS race at boot | Services `after = [ sops-nix.service ]` (Stufe 9) |
| Journal flood bei `-vv` | Log-Level in Timern begrenzen |

Storage-Mover: `rclone move` von Tier-B-Cache → Tier-C mit `--min-age 30d`.

## restic

| Risiko | Mitigation |
|--------|------------|
| DB write drift | `backupPrepareCommand` stoppt PostgreSQL + Apps |
| MediaCover bloat | `exclude` in `30-storage.nix` |
| Netzwerk nicht ready | Timer nach `network-online.target` |

```bash
systemctl status restic-backups-tier-a-sovereign.timer
restic -r s3:... snapshots   # mit env aus /var/lib/secrets/restic_s3_creds
```

## SSoT

Pfade, Timer und Excludes leben in `modules/30-storage.nix`; Geräte/Labels in `machines/q958/profile.nix`.