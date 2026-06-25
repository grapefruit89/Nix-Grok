---
meta:
  role: doc
  purpose: ADR-005 Restart=always für kritische Dienste
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - systemd
---

# ADR-005: Kritische Dienste — Restart=always ohne Rate-Limit

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext

- Blocky, Caddy und DNS-Ausfall machen das Homelab sofort unbenutzbar.
- cgroup-OOM (ADR-003) kann einzelne Dienste killen — sie müssen danach zuverlässig zurückkommen.
- Standard-`Restart=on-failure` mit StartLimit kann nach wiederholten Crashes stoppen.

## Entscheidung

1. **Preset:** `lib/critical-systemd.nix` — `Restart=always`, `StartLimitIntervalSec=0`, negativer `OOMScoreAdjust`.
2. **Anwenden auf:** Blocky, Caddy, Pocket-ID (Ingress/Identität).
3. **Gatus** prüft Blocky + Caddy als kritische Endpoints.

## Konsequenzen

### Positiv

- Kurzer Ausfall → automatische Wiederherstellung ohne manuelles `systemctl restart`.
- OOM auf Infrastruktur unwahrscheinlicher (negativer Score).

### Negativ

- Endlos-Crash-Loop ohne externes Alerting schwerer sichtbar — Gatus/Journald beobachten.
- Nicht für alle Apps (RAM-Fresser) — nur Tier-0/1.

### Implementierung

| Artefakt | Pfad |
|----------|------|
| Preset | `lib/critical-systemd.nix` |
| Nutzer | `modules/10-network.nix`, `modules/60-apps/default.nix` |
| Audit | `docs/AUDIT-blocky-caddy-ipv6.md` §10 |