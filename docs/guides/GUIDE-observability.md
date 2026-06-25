---
meta:
  role: doc
  purpose: Betriebsguide Gatus, VLG-Logging, CrowdSec, Alerting
  docs:
    - modules/40-observability.nix
    - modules/05-alerting.nix
  tags:
    - observability
    - gatus
    - crowdsec
---

# Observability Guide

> Gatus-Healthchecks, Vector→Loki→Grafana, CrowdSec, ntfy-Alerting.

## Gatus

- Endpunkte: `lib/gatus-endpoints.nix` (generiert aus `my.ports` + Rollout)
- UI: Caddy SSO (`gatus.<domain>`)
- Storage-Checks: SSH-Wrapper `gatus-ssh-wrapper` — Timeout 20s für HDD spin-up

```bash
systemctl status gatus.service
curl -s http://127.0.0.1:$(nix eval --raw .#q958 2>/dev/null || echo 8084)/health  # Port aus my.ports.gatus
```

## Unix-Socket-Checks

Gatus kann keine UDS direkt — Prüfskripte laufen per eingeschränktem SSH-User `monitoring`:

```
restrict,command="/run/current-system/sw/bin/gatus-ssh-wrapper" <key>
```

## VLG (Vector / Loki / Grafana)

1. Vector liest journald, parst Caddy-JSON (VRL)
2. Loki: `/var/lib/loki`, 7d Retention
3. Grafana: SSO, Loki-Datasource vorkonfiguriert

## CrowdSec

- LAPI: `127.0.0.1:<my.ports.crowdsec>`
- Bouncer: nftables-Integration über Firewall-Modul
- Aktivierung: Rollout Stufe 8

## Alerting (`05-alerting.nix`)

- ntfy-Topic / Webhook aus `machines/q958/profile.nix` → `alerting.*`
- Restic: Dead-Man-Switch via `healthcheckUrl` nach Backup

## Rollout

| Stufe | Dienst |
|-------|--------|
| 4 | observability, gatus |
| 8 | crowdsec, fail2ban, alerting |