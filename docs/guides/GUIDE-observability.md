---
meta:
  role: doc
  purpose: Betriebsguide Gatus, VLG-Logging, CrowdSec, Alerting
  docs:
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/005-critical-systemd-restart.md
    - modules/40-observability.nix
    - modules/05-alerting.nix
  tags:
    - observability
    - gatus
    - crowdsec
---

# Observability Guide {#guide-observability}

> Gatus-Healthchecks, Vector→Loki→Grafana, CrowdSec, ntfy-Alerting.

## Gatus {#gatus}

- Endpunkte: `lib/gatus-endpoints.nix` (generiert aus `my.ports` + Rollout)
- UI: Caddy SSO (`gatus.<domain>`)
- Storage-Checks: SSH-Wrapper `gatus-ssh-wrapper` — Timeout 20s für HDD spin-up

```bash
systemctl status gatus.service
curl -s http://127.0.0.1:$(nix eval --raw .#q958 2>/dev/null || echo 4003)/health  # Port aus my.ports.gatus
```

## Unix-Socket-Checks {#unix-socket-checks}

Gatus kann keine UDS direkt — Prüfskripte laufen per eingeschränktem SSH-User `monitoring`:

```
restrict,command="/run/current-system/sw/bin/gatus-ssh-wrapper" <key>
```

## VLG (Vector / Loki / Grafana) {#vlg}

1. Vector liest journald, parst Caddy-JSON (VRL)
2. Loki: `/var/lib/loki`, 7d Retention
3. Grafana: SSO, Loki-Datasource vorkonfiguriert

OOM-Schutz: Loki MemoryMax 512M, Grafana 512M — Tier 3 ([ADR-003 Tier-Modell](../adr/003-oom-cgroup-isolation.md#tier-modell)).

## CrowdSec {#crowdsec}

- LAPI: `127.0.0.1:<my.ports.crowdsec>`
- Bouncer: nftables-Integration über Firewall-Modul (`15-firewall.nix`)
- Aktivierung: Rollout Stufe 8

## Alerting (`05-alerting.nix`) {#alerting}

- ntfy-Topic / Webhook aus `machines/q958/profile.nix` → `alerting.*`
- Restic: Dead-Man-Switch via `healthcheckUrl` nach Backup
- Service-Neustarts: `Restart=always` auf kritischen Diensten ([ADR-005](../adr/005-critical-systemd-restart.md))

## Rollout {#rollout}

| Stufe | Dienst |
|-------|--------|
| 4 | observability, gatus |
| 8 | crowdsec, fail2ban, alerting |

## Siehe auch {#siehe-auch}

- [ADR-003 — OOM-Isolation](../adr/003-oom-cgroup-isolation.md) — MemoryMax für Loki, Grafana, Vector
- [ADR-005 — Restart=always](../adr/005-critical-systemd-restart.md) — Restart-Policy für kritische Observability-Services
- [GUIDE-observability-kurz.md](GUIDE-observability-kurz.md) — Täglicher Kurzguide (2-Minuten-Check)
- [GUIDE-nftables-hardening.md#fail2ban](GUIDE-nftables-hardening.md#fail2ban) — Fail2ban↔nftables für Ban-Sets
