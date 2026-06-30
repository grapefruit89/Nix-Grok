---
meta:
  role: doc
  purpose: ADR-003 RAM-Isolation per systemd cgroup — OOM-Kill-Isolation pro Service
  status: accepted
  date: 2026-06-17
  error_pattern: "oom-kill.*\\.service|memory cgroup out of memory|killed process.*memory.cgroup"
  quick_fix: "MemoryMax in lib/memory-policy.nix erhöhen + systemctl restart <service>"
  services: [jellyfin, postgresql, sabnzbd, loki, paperless-ngx, caddy, home-assistant]
  betrifft:
    - lib/memory-policy.nix
    - lib/critical-systemd.nix
  docs:
    - docs/adr/README.md
    - docs/memory_oom.md
    - docs/adr/001-dns-dot-fail-closed.md
    - docs/adr/005-critical-systemd-restart.md
    - docs/RUNBOOK.md
  tags:
    - adr
    - oom
    - memory
    - cgroup
    - systemd
---

# ADR-003: OOM- und RAM-Isolation per systemd cgroup {#adr-003}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 (32 GB RAM) |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Homelab läuft viele RAM-lastige Dienste (PostgreSQL ~8G `shared_buffers`, Jellyfin-Transcode, SABnzbd Par2, Loki, Paperless-OCR).
- Ein Leak oder Spike in **einer** App darf nicht SSH, Blocky oder das ganze System via Kernel-OOM-Killer destabilisieren.
- `OOMScoreAdjust` allein reicht nicht — ohne `MemoryMax` kann ein Dienst unbegrenzt wachsen, bevor der globale OOM greift.
- `Restart=always` ([ADR-005](005-critical-systemd-restart.md)) hilft nach Dienst-Crash, ersetzt aber keine cgroup-Käfigwand.
- Blocky als kritischer DNS-Resolver bekommt Tier-0-Schutz und MemoryMax 500M ([ADR-001](001-dns-dot-fail-closed.md)).

## Entscheidung {#entscheidung}

**Zwei Mechanismen kombinieren, eine Wahrheit (`lib/memory-policy.nix`):**

1. `MemoryMax` / `MemoryHigh` → Überschreitung killt **nur** den Dienst/Slice (cgroup-OOM).
2. `OOMScoreAdjust` → bei systemweitem Notstand: Infrastruktur später, Apps früher getötet.

### Tier-Modell {#tier-modell}

| Tier | Dienste | OOMScoreAdjust | Beispiel MemoryMax |
|------|---------|----------------|--------------------|
| 0 — Infra-kritisch | Blocky, SSH, Tailscale | −900 | 500M |
| 1 — Ingress | Caddy, Pocket-ID | −500 | 768M |
| 2 — Daten | PostgreSQL | −200 | skaliert mit RAM |
| 3 — Observability | Grafana, Loki, Vector | +100 | 512M |
| 4 — Media | Jellyfin, SABnzbd, *arr | +200 | 12G / 4G |
| 5 — Apps | Paperless, Vaultwarden | +300 | 2G |

### Implementierungsstand {#implementierungsstand}

- **P1 implementiert:** PostgreSQL, Jellyfin, SABnzbd, Loki, Paperless (`system-paperless.slice` 2G).
- **P2 implementiert:** *arr, Caddy 768M, Pocket-ID 256M, Vector/Grafana 512M.
- **P3 offen:** nix-daemon bei Rebuilds, systemd-oomd optional.
- **Postgres-Caps** skalieren mit `hardware.ramGB` aus `profile.nix` — keine Magic Numbers in Modulen.

## Diagnose {#diagnose}

**Symptom:** Service gestoppt, `systemctl status <service>` zeigt `(Result: oom-kill)` oder `Exit: signal`.

```bash
# OOM-Events im Kernel-Log (letzte 7 Tage)
journalctl -k --no-pager | grep -iE "oom.kill|killed process|out of memory"

# Welcher Service, welche Zeit?
journalctl -b --no-pager | grep -iE "memory.*cgroup|oom.kill" | tail -20

# Aktuell konfigurierte Limits anzeigen
systemctl show jellyfin postgresql caddy sabnzbd \
  -p MemoryMax,MemoryHigh,OOMScoreAdjust --no-pager

# Wieviel RAM verbraucht jeder Service gerade?
systemd-cgtop -n1
```

**Erwarteter Output bei OOM-Kill:**
```
kernel: oom-kill: constraint=CONSTRAINT_MEMCG, ... task=jellyfin ...
kernel: Memory cgroup out of memory: Killed process 12345 (jellyfin) ...
systemd[1]: jellyfin.service: A process of this unit has been killed by the OOM killer.
```

## Fix {#fix}

```bash
# 1. Betroffenen Service + aktuelles Limit identifizieren
journalctl -k | grep -i "oom-kill" | tail -5
systemctl show <service> -p MemoryMax

# 2. In lib/memory-policy.nix: MemoryMax-Preset erhöhen
#    Beispiel: jellyfin MemoryMax = "12G" → "16G"
grep -n "MemoryMax\|jellyfin\|sabnzbd" /etc/nixos/lib/memory-policy.nix

# 3. Dry-build + Switch
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
# in tmux: sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure

# 4. Service neu starten (falls gestoppt)
sudo systemctl restart <service>

# 5. Caps-Übersicht prüfen
systemctl show postgresql jellyfin caddy -p MemoryMax,MemoryHigh
```

Vollständige Cap-Tabelle: [docs/memory_oom.md](../memory_oom.md)

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- RAM-Fresser stirbt isoliert; Infrastruktur (SSH, Caddy, Blocky) bleibt erreichbar.
- KI/Mensch finden alle Limits zentral in `lib/memory-policy.nix` + [memory_oom.md](../memory_oom.md).
- Nach cgroup-Kill greift `Restart=always` auf kritischen Diensten ([ADR-005](005-critical-systemd-restart.md)).

### Negativ / Trade-offs {#negativ}

- Zu enge Caps → Dienst-OOM unter Last (Jellyfin-Transcode, Postgres-Vacuum) — erfordert Beobachtung.
- Summe der Caps > 32G ist ok (nicht alle Spitzen gleichzeitig), aber Planung nötig.
- P3 offen: nix-daemon bei Rebuilds, systemd-oomd optional.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Presets (eine Wahrheit) | `lib/memory-policy.nix` |
| Kritische Restart-Policy | `lib/critical-systemd.nix` |
| Cap-Tabelle (Referenz) | `docs/memory_oom.md` |
| *arr-Fabrik | `modules/50-media/arr-helper.nix` |

### Verifikation {#verifikation}

```bash
systemctl show postgresql jellyfin caddy system-paperless.slice \
  -p MemoryMax,MemoryHigh,OOMScoreAdjust
journalctl -k --no-pager | grep -iE 'oom|out of memory' --since '7 days ago'
```

## Alternativen verworfen {#alternativen}

- **systemd-oomd** — NixOS-Integration instabil (2026), überlässt Kill-Entscheidung dem System statt feingranularer Caps je Dienst. Kann als P3 ergänzt werden, ersetzt aber nicht `MemoryMax`.
- **ulimit / PAM-Limits** — wirkt nur pro-Prozess, keine cgroup-Isolation, kein `MemoryHigh`-Druck-Mechanismus.
- **Kein MemoryMax** — `OOMScoreAdjust` allein ist zu spät: Dienst frisst bis zum globalen Kernel-OOM bevor Score greift.
- **Feste Caps unabhängig von Hardware** — Magic Numbers in Modulen brechen auf Maschinen mit anderem RAM; stattdessen: `hardware.ramGB`-Skalierung.

## Siehe auch {#siehe-auch}

- [ADR-001 — DNS-over-TLS](001-dns-dot-fail-closed.md) — Blocky als Tier-0-Dienst, MemoryMax 500M
- [ADR-005 — Restart=always](005-critical-systemd-restart.md) — Neustart nach cgroup-Kill
- [docs/memory_oom.md](../memory_oom.md) — vollständige Cap-Tabelle aller Dienste
- [RUNBOOK — Jellyfin OOM](../RUNBOOK.md#jellyfin) — Quick-Fix bei Jellyfin-OOM-Kill
- [GUIDE-media-stack.md#jellyfin](../guides/GUIDE-media-stack.md#jellyfin) — Jellyfin MemoryMax 12G, SABnzbd Tier-4
- [GUIDE-observability.md#vlg](../guides/GUIDE-observability.md#vlg) — Loki/Grafana MemoryMax 512M (Tier 3)
- [GUIDE-storage-tiers.md](../guides/GUIDE-storage-tiers.md) — SABnzbd auf Tier B, Restic stoppt PostgreSQL
