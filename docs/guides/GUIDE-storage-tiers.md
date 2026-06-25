---
meta:
  role: doc
  purpose: Betriebsguide Storage-Tiers, Impermanence, Restic, Pending-Watcher
  docs:
    - machines/q958/profile.nix
    - modules/30-storage.nix
  tags:
    - storage
    - tiers
    - restic
---

# Storage Tiers Guide

> Tier A/B/C-Regeln, Impermanence, MergerFS, Pending-Disks, Restic-Excludes.

## Tier-Policy (q958)

| Tier | Medium | Bus | Labels | Rolle |
|------|--------|-----|--------|-------|
| A | SSD | SATA (`/dev/sda`) | NIXBOOT, NIXPERSIST, NIXSTORE | System, DB, Secrets |
| B | SSD | SATA only | NIXDATA, TIER_B_* | Fast pool, Downloads-Cache |
| C | HDD | — | NIXMEDIA, NIXBACKUP | Cold / Media |

**Harte Regeln:** A/B kein spinning; B nie NVMe; C immer HDD.  
q958 singleDisk: `mergerfsEnable = false` bis Branches existieren.

## Impermanence (Stufe 9)

- Root: tmpfs 16G
- Persist: `storage.impermanence.mountPoint` (z. B. `/persist`)
- `systemd.tmpfiles.rules` legt Persist-Unterverzeichnisse für Tier-A-Pfade an
- Journal: bind nach `/var/log/journal` auf Persist

## MediaCover / Cache (Tier B)

Metadata außerhalb von `/var/lib/*arr`:

```
/mnt/fast_pool/metadata/{sonarr,radarr,prowlarr,jellyfin}
```

Stub-Pfade bei singleDisk: `machines/q958/storage.nix` → `tmpfiles.rules`.

## Pending Disks Watcher

Unlabelierte Disks → `/run/nixhome-pending-disks/*.pending`

```bash
ls /run/nixhome-pending-disks/
systemctl status nixhome-pending-watcher.timer
```

**Wichtig:** Schreibpfad ist `/run/nixhome-pending-disks`, nicht `/run/pending-disks`.

## Restic

Excludes (kein Bloat im Offsite-Backup):

- `**/MediaCover`, `**/cache/**`, `/mnt/fast_pool/cache`

Aktivierung: `rollout.stufe` ≥ 6 wenn `restic.offsiteEnable`.

## Storage Mover

Hysterese: SSD ≥ 85% oder HDDs bereits spinning → `rclone move` Tier B → C.  
Timer: `nixhome-storage-mover.timer`.

## Deferred Deletion (HDD-sparend)

Große Löschungen auf Tier C nicht sofort — zuerst in die SSD-Queue:

```bash
nixhome-defer-delete /mnt/media/some/old/library
systemctl start process-delete-queue   # oder stündlicher Timer
```

- Queue: `/mnt/fast_pool/delete_queue` (Tier B)
- Löscht nur Pfade unter `tierC.mountPoint` oder `/mnt/tier-c/*`
- HDD aktiv → sofort; HDD schläft → erst nach 7 Tagen (konfigurierbar)
- Rollout: ab Stufe 3 (`my.storage.deferred.enable`)