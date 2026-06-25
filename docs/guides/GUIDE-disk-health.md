---
meta:
  role: doc
  purpose: Betriebsguide smartd + Scrutiny für Tier-C HDDs
  docs:
    - modules/36-disk-health.nix
  tags:
    - storage
    - smartd
    - scrutiny
---

# Disk Health — smartd + Scrutiny

> Tier-C HDDs (NIXMEDIA, NIXBACKUP) — SMART-Monitoring ohne Docker.

## Dienste

| Dienst | Rolle |
|--------|-------|
| `smartd` | DEVICESCAN, `-n standby` Spindown nach 30min |
| `scrutiny` | WebUI + Historie, liest smartd-Daten |

Rollout: Stufe 3+ (`my.disk-health.enable` in `rollout.nix`).

## UI

- Scrutiny: `https://scrutiny.<domain>` (admin-hangar / Tailscale)
- Lokal: `http://127.0.0.1:8086/health`

## Checks (Gatus)

- `smartd-active` — Dienst läuft
- `scrutiny-health` — WebUI erreichbar
- `hdd-smart` — alle rotational devices `PASSED` (OK wenn keine HDD da)

## Betrieb

```bash
systemctl status smartd scrutiny
smartctl -H /dev/sdX          # manuell
journalctl -u smartd -n 30
```

HDD spin-up: erste SMART-Abfrage nach Standby kann 10–20s dauern — Gatus-Timeout berücksichtigt das.