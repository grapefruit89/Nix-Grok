---
meta:
  role: doc
  purpose: ADR-005 Restart=always für kritische Dienste — kein Rate-Limit, negativer OOM-Score
  status: accepted
  date: 2026-06-17
  error_pattern: "Start request repeated too quickly|entered failed state|failed.*StartLimitHit"
  quick_fix: "systemctl reset-failed <service> && systemctl start <service>"
  services: [caddy, technitium, pocket-id]
  betrifft:
    - lib/critical-systemd.nix
    - modules/10-network/11-network.nix
    - modules/60-apps/pocket-id.nix
  docs:
    - docs/adr/README.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/007-dendritic-one-file-per-service.md
  tags:
    - adr
    - systemd
    - restart
    - kritisch
---

# ADR-005: Kritische Dienste — Restart=always ohne Rate-Limit {#adr-005}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext {#kontext}

- Caddy, Technitium/DNS und Pocket-ID machen das Homelab sofort unbenutzbar wenn sie ausfallen.
- cgroup-OOM ([ADR-003](003-oom-cgroup-isolation.md)) kann einzelne Dienste killen — sie müssen danach zuverlässig zurückkommen.
- Standard-`Restart=on-failure` mit StartLimit kann nach wiederholten Crashes stoppen.

## Entscheidung {#entscheidung}

1. **Preset:** `lib/critical-systemd.nix` — `Restart=always`, `StartLimitIntervalSec=0`, negativer `OOMScoreAdjust`.
2. **Anwenden auf:** Caddy, Technitium/DNS ([ADR-001](001-dns-dot-fail-closed.md)), Pocket-ID (Ingress/Identität).
3. **Gatus** prüft Caddy + DNS als kritische Endpoints.

## Diagnose {#diagnose}

**Symptom:** Dienst startet endlos-schnell durch (Crash-Loop) ohne in `active` zu kommen.

```bash
# Crash-Loop erkennen
systemctl status caddy --no-pager
journalctl -u caddy -n 50 --no-pager | grep -iE "error|fail|start"

# Alle fehlgeschlagenen Dienste
systemctl list-units --state=failed

# Rate-Limit-Treffer (tritt bei Standard-Restart-Policy auf, nicht bei dieser)
journalctl -u caddy --no-pager | grep "Start request repeated too quickly"
```

## Fix {#fix}

```bash
# 1. Fehlerursache identifizieren (nicht einfach neu starten!)
journalctl -u <service> -n 100 --no-pager | grep -iE "error|fail|fatal"

# 2. Nach manueller Behebung: Failed-State zurücksetzen
sudo systemctl reset-failed <service>
sudo systemctl start <service>

# 3. Falls Crash-Loop auf anderen Diensten ohne critical-systemd:
#    → Preset in lib/critical-systemd.nix anwenden
grep -n "Restart\|StartLimit" /etc/nixos/lib/critical-systemd.nix
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Kurzer Ausfall → automatische Wiederherstellung ohne manuelles `systemctl restart`.
- OOM auf Infrastruktur unwahrscheinlicher (negativer Score, [ADR-003](003-oom-cgroup-isolation.md#tier-modell)).

### Negativ {#negativ}

- Endlos-Crash-Loop ohne externes Alerting schwerer sichtbar — Gatus/Journald beobachten.
- Nicht für alle Apps (RAM-Fresser) — nur Tier-0/1 ([ADR-003](003-oom-cgroup-isolation.md#tier-modell)).

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Preset | `lib/critical-systemd.nix` |
| Nutzer | `modules/10-network/11-network.nix`, `modules/60-apps/pocket-id.nix` |
| Audit | `docs/AUDIT-blocky-caddy-ipv6.md` §10 |

## Alternativen verworfen {#alternativen}

- **`Restart=on-failure` mit StartLimit** — stoppt nach N Crashes; Tier-0-Dienste müssen aber immer zurückkommen. Abgelehnt für kritische Dienste.
- **Manuelle Wiederherstellung** — nicht akzeptabel für DNS/Ingress, die alles andere blockieren. Abgelehnt.
- **Watchdog-Service extern** — unnötige Komplexität wenn systemd `Restart=always` leistet. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-003 — OOM-Isolation](003-oom-cgroup-isolation.md) — cgroup-OOM-Kill der diesen Restart auslöst
- [ADR-001 — DNS-over-TLS](001-dns-dot-fail-closed.md) — Technitium als kritischer Dienst mit Restart=always
- [ADR-007 — Dendritische Module](007-dendritic-one-file-per-service.md) — Modulstruktur in der critical-systemd.nix eingebunden wird
- [GUIDE-observability.md#alerting](../guides/GUIDE-observability.md#alerting) — Alerting auf Restart-Basis, ntfy bei OnFailure
