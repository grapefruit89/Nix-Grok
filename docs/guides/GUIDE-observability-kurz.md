---
meta:
  role: doc
  purpose: Täglicher Kurzguide — Gatus, Logs, Alerts (ohne Uptime Kuma)
  docs:
    - docs/guides/GUIDE-observability.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/005-critical-systemd-restart.md
  tags:
    - observability
    - kurzguide
---

# Observability — Kurzguide {#guide-observability-kurz}

> Ein Blatt für den Alltag. Vollständige Details: [GUIDE-observability.md](GUIDE-observability.md).

## Morgens (2 Minuten) {#morgens}

1. **Gatus** — `https://gatus.<domain>` (Tailscale/LAN)
   - Gruppe `critical`: `caddy-ingress`, `blocky-dns` müssen grün sein
   - Gruppe `core`: `postgresql` grün (Pocket-ID, Apps)
2. **Boot-Watchdog** — einmal nach Reboot:
   ```bash
   systemctl status boot-watchdog.service
   journalctl -u boot-watchdog -b --no-pager
   ```

## Bei rotem Gatus-Check {#roter-check}

| Check | Erste Aktion |
|-------|----------------|
| `caddy-ingress` | `systemctl status caddy` → `journalctl -u caddy -n 50` |
| `blocky-dns` | `systemctl restart blocky` → DNS `dig @127.0.0.1 cloudflare.com` |
| `postgresql` | `systemctl status postgresql` → `pg_isready -h /run/postgresql` |
| `mergerfs-media-pool` | HDD spin-up: 20–25s normal; `ls /mnt/tier-c/` |
| `hdd-smart` | `smartctl -H /dev/sdX` → Scrutiny UI |

## Logs (VLG) {#logs}

| Was | Wo |
|-----|-----|
| Caddy-Zugriffe | Grafana → Loki → `{job="vector"}` + `| json | host=` |
| Systemd-Fehler | `journalctl -p err -b` |
| CrowdSec-Bans | `cscli decisions list` (Stufe 8+) |

Grafana: `https://grafana.<domain>` — Datasource Loki ist vorkonfiguriert.

## Alerts (Stufe 8+) {#alerts}

- **ntfy**-Topic aus `machines/q958/profile.nix` → `alerting.ntfyTopic`
- Auslöser: `boot-watchdog`, `usenet`, Restic `OnFailure`
- Runtime-Sicherheit: `systemctl status security-watchdog.timer` (stündlich)

## Was wir nicht nutzen {#nicht-genutzt}

- **Uptime Kuma** — nicht im Stack; Gatus deckt HTTP/TCP/DNS/SSH-Checks ab
- **Grafana als Uptime-Dashboard** — nur Logs/Metriken, Health = Gatus

## Schnellbefehle {#schnellbefehle}

```bash
tools/post-switch-check.sh          # gatus loki grafana vector
systemctl list-units --failed
curl -s http://127.0.0.1:4003/health   # Gatus lokal
```

## Siehe auch {#siehe-auch}

- [GUIDE-observability.md](GUIDE-observability.md) — vollständiger Betriebsguide (VLG, CrowdSec, Rollout)
- [ADR-003 — OOM-Isolation](../adr/003-oom-cgroup-isolation.md) — wenn ein Service im Check fehlt wegen OOM-Kill
- [ADR-005 — Restart=always](../adr/005-critical-systemd-restart.md) — Restart-Policy für kritische Services
- [RUNBOOK.md](../RUNBOOK.md) — Quick-Fix bei Caddy-, Arr- oder Jellyfin-Problemen
