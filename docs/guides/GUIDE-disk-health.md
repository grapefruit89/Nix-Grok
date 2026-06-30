---
meta:
  role: doc
  purpose: Betriebsguide smartd + Scrutiny für Tier-C HDDs
  docs:
    - docs/guides/GUIDE-storage-tiers.md
    - docs/guides/GUIDE-observability.md
    - modules/36-disk-health.nix
  tags:
    - storage
    - smartd
    - scrutiny
---

# Disk Health — smartd + Scrutiny {#guide-disk-health}

> Tier-C HDDs (NIXMEDIA, NIXBACKUP) — SMART-Monitoring ohne Docker.

## Dienste {#dienste}

| Dienst | Rolle |
|--------|-------|
| `smartd` | DEVICESCAN, `-n standby` Spindown nach 30min |
| `scrutiny` | WebUI + Historie, liest smartd-Daten |

Rollout: Stufe 3+ (`my.disk-health.enable` in `rollout.nix`).

## UI {#ui}

- Scrutiny: `https://scrutiny.<domain>` (admin-hangar / Tailscale)
- Lokal: `http://127.0.0.1:4005/health`

## Checks (Gatus) {#gatus-checks}

- `smartd-active` — Dienst läuft
- `scrutiny-health` — WebUI erreichbar
- `hdd-smart` — alle rotational devices `PASSED` (OK wenn keine HDD da)

Gatus-Integration: [GUIDE-observability.md#gatus](GUIDE-observability.md#gatus).

## Betrieb {#betrieb}

```bash
systemctl status smartd scrutiny
smartctl -H /dev/sdX          # manuell
journalctl -u smartd -n 30
```

HDD spin-up: erste SMART-Abfrage nach Standby kann 10–20s dauern — Gatus-Timeout berücksichtigt das.

## Siehe auch {#siehe-auch}

- [GUIDE-storage-tiers.md](GUIDE-storage-tiers.md) — Tier-C HDD Regeln, Pending-Watcher, Deferred Deletion
- [GUIDE-observability.md#gatus](GUIDE-observability.md#gatus) — Gatus-Checks für smartd und Scrutiny
- [GUIDE-data-management.md](GUIDE-data-management.md) — Restic-Backup auf Tier C
