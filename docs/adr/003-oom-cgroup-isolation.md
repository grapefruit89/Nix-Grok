---
meta:
  role: doc
  purpose: ADR-003 RAM-Isolation per systemd cgroup
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - oom
---

# ADR-003: OOM- und RAM-Isolation per systemd cgroup

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 (32 GB RAM) |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Homelab läuft viele RAM-lastige Dienste (PostgreSQL ~8G `shared_buffers`, Jellyfin-Transcode, SABnzbd Par2, Loki, Paperless-OCR).
- Ein Leak oder Spike in **einer** App darf nicht SSH, Blocky oder das ganze System via Kernel-OOM-Killer destabilisieren.
- `OOMScoreAdjust` allein reicht nicht — ohne `MemoryMax` kann ein Dienst unbegrenzt wachsen, bevor der globale OOM greift.
- `Restart=always` (`lib/critical-systemd.nix`) hilft nach Dienst-Crash, ersetzt aber keine cgroup-Käfigwand.

## Entscheidung

1. **Zwei Mechanismen kombinieren:**
   - `MemoryMax` / `MemoryHigh` → Überschreitung killt **nur** den Dienst/Slice (cgroup-OOM).
   - `OOMScoreAdjust` → bei systemweitem Notstand: Infrastruktur später, Apps früher getötet.
2. **Eine Wahrheit:** `lib/memory-policy.nix` — Presets pro Tier, Module nur `mkMerge`.
3. **Tier-Modell** (Kurz):
   - Tier 0: Blocky, SSH, Tailscale — Score negativ, kleine Caps
   - Tier 1: Caddy, Postgres, Pocket-ID — Score negativ/moderat, Caps
   - Tier 3–5: Observability, Media, Apps — positive Scores + harte Caps
4. **P1 implementiert:** Postgres, Jellyfin, SABnzbd, Loki, Paperless (`system-paperless.slice` 2G).
5. **P2 implementiert:** *arr, Caddy 768M, Pocket-ID 256M, Vector/Grafana 512M.
6. **Postgres-Caps** skalieren mit `hardware.ramGB` aus `profile.nix` — keine Magic Numbers in Modulen.
7. **Paperless:** Budget auf nixpkgs-`system-paperless.slice`, nicht eigene Slice (Konflikt vermeiden).

## Konsequenzen

### Positiv

- RAM-Fresser stirbt isoliert; Infrastruktur bleibt erreichbar.
- KI/Mensch finden Limits zentral in `memory_oom.md` + `memory-policy.nix`.
- Nach cgroup-Kill: `Restart=always` auf kritischen Diensten.

### Negativ / Trade-offs

- Zu enge Caps → Dienst-OOM unter Last (Jellyfin-Transcode, Postgres) — Caps müssen an Beobachtung angepasst werden.
- Summe der Caps > 32G ist ok (nicht alle Spitzen gleichzeitig), aber Planung nötig.
- P3 offen: nix-daemon bei Rebuilds, systemd-oomd optional.

### Implementierung

| Artefakt | Pfad |
|----------|------|
| Presets | `lib/memory-policy.nix` |
| Kritische Restart-Policy | `lib/critical-systemd.nix` |
| Referenz / Tabelle | `docs/memory_oom.md` |
| *arr-Fabrik | `modules/50-media/arr-helper.nix` |

### Verifikation

```bash
systemctl show postgresql jellyfin caddy system-paperless.slice \
  -p MemoryMax,MemoryHigh,OOMScoreAdjust
journalctl -k -g 'oom|Out of memory' --since '7 days ago'
```

## Verwandte ADRs

- [001 — DNS](001-dns-dot-fail-closed.md) (Blocky Tier 0, MemoryMax 500M)