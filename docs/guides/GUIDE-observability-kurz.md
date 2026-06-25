---
meta:
  role: doc
  purpose: Täglicher Kurzguide — Gatus, Logs, Alerts (ohne Uptime Kuma)
  docs:
    - docs/guides/GUIDE-observability.md
  tags:
    - observability
    - kurzguide
---

# Observability — Kurzguide

> Ein Blatt für den Alltag. Vollständige Details: [GUIDE-observability.md](GUIDE-observability.md).

## Morgens (2 Minuten)

1. **Gatus** — `https://gatus.<domain>` (Tailscale/LAN)
   - Gruppe `critical`: `caddy-ingress`, `blocky-dns` müssen grün sein
   - Gruppe `core`: `postgresql` grün (Pocket-ID, Apps)
2. **Boot-Watchdog** — einmal nach Reboot:
   ```bash
   systemctl status boot-watchdog.service
   journalctl -u boot-watchdog -b --no-pager
   ```

## Bei rotem Gatus-Check

| Check | Erste Aktion |
|-------|----------------|
| `caddy-ingress` | `systemctl status caddy` → `journalctl -u caddy -n 50` |
| `blocky-dns` | `systemctl restart blocky` → DNS `dig @127.0.0.1 cloudflare.com` |
| `postgresql` | `systemctl status postgresql` → `pg_isready -h /run/postgresql` |
| `mergerfs-media-pool` | HDD spin-up: 20–25s normal; `ls /mnt/tier-c/` |
| `hdd-smart` | `smartctl -H /dev/sdX` → Scrutiny UI |

## Logs (VLG)

| Was | Wo |
|-----|-----|
| Caddy-Zugriffe | Grafana → Loki → `{job="vector"}` + `| json | host=` |
| Systemd-Fehler | `journalctl -p err -b` |
| CrowdSec-Bans | `cscli decisions list` (Stufe 8+) |

Grafana: `https://grafana.<domain>` — Datasource Loki ist vorkonfiguriert.

## Alerts (Stufe 8+)

- **ntfy**-Topic aus `machines/q958/profile.nix` → `alerting.ntfyTopic`
- Auslöser: `boot-watchdog`, `usenet`, Restic `OnFailure`
- Runtime-Sicherheit: `systemctl status security-watchdog.timer` (stündlich)

## Was wir nicht nutzen

- **Uptime Kuma** — nicht im Stack; Gatus deckt HTTP/TCP/DNS/SSH-Checks ab
- **Grafana als Uptime-Dashboard** — nur Logs/Metriken, Health = Gatus

## Schnellbefehle

```bash
tools/post-switch-check.sh          # gatus loki grafana vector
systemctl list-units --failed
curl -s http://127.0.0.1:8084/health   # Gatus lokal
```