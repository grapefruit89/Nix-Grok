---
meta:
  role: doc
  purpose: RAM/OOM-Policy — cgroup-Limits und Tier-Modell
  docs:
    - docs/adr/003-oom-cgroup-isolation.md
  lib:
    - lib/memory-policy.nix
  tags:
    - oom
    - systemd
---

# Memory & OOM Policy — q958 Homelab

> **Host:** q958 · **RAM:** 32 GB (`machines/q958/profile.nix` → `hardware.ramGB`)  
> **Implementierung:** `lib/memory-policy.nix`

## 1. Ziel

**Ein Dienst mit RAM-Fehler oder Speicher-Leak darf das Betriebssystem nicht mitreißen.**

Dafür zwei komplementäre Mechanismen:

| Mechanismus | Wirkung | Konfiguration |
|-------------|---------|---------------|
| **`MemoryMax` / `MemoryHigh`** | cgroup-Limit — Überschreitung killt **nur diesen** Dienst (bzw. Slice) | `systemd.services.*.serviceConfig` oder `systemd.slices.*` |
| **`OOMScoreAdjust`** | Bei **systemweitem** RAM-Notstand: niedriger Score = später vom Kernel getötet | gleiche `serviceConfig` |

`Restart=always` (siehe `lib/critical-systemd.nix`) startet den Dienst nach cgroup-OOM neu — ersetzt aber **kein** `MemoryMax`.

---

## 2. Tier-Modell

| Tier | Rolle | OOM-Score (typ.) | MemoryMax |
|------|-------|------------------|-----------|
| **0** | Lebensader (DNS, SSH, Tailscale) | -1000 … -900 | klein, wo sinnvoll |
| **1** | Ingress, DB, Identität | -800 … -500 | moderat / RAM-basiert |
| **2** | IoT-Bus | -100 … 0 | klein |
| **3** | Observability | +200 … +300 | 512M–1G |
| **4** | Media / Downloads | +100 … +300 | 2G–6G |
| **5** | Apps (HA, Paperless, …) | +200 … +300 | 512M–2G |

**Regel für KI:** RAM-Fresser → `MemoryMax` **und** positiver `OOMScoreAdjust`. Infrastruktur → negativer Score, optionales Cap.

---

## 3. Implementierung — `lib/memory-policy.nix`

```nix
memory = import ../../lib/memory-policy.nix { inherit lib; };

# Einzelner Dienst
systemd.services.jellyfin.serviceConfig = lib.mkMerge [
  { /* hardening */ }
  (memory.jellyfin { })
];

# RAM-abhängig (Postgres)
systemd.services.postgresql.serviceConfig = lib.mkMerge [
  { /* hardening */ }
  (memory.postgres ramGB)
];

# Mehrere Units, ein Budget (Paperless)
systemd.slices.paperless.sliceConfig = memory.paperless.slice;
systemd.services.paperless-web.serviceConfig = lib.mkMerge [
  memory.paperless.service
  { Slice = memory.paperless.sliceName; }
];
```

### API

| Funktion | Rückgabe | Verwendung |
|----------|----------|------------|
| `mkServiceLimits { … }` | `serviceConfig`-Attrs | Generisch |
| `postgres ramGB` | Caps aus `ramGB` | PostgreSQL |
| `jellyfin { }` | 6G / High 4G, OOM +100 | Jellyfin |
| `sabnzbd { }` | 2G, OOM +300 | SABnzbd |
| `loki { }` | 1G, OOM +300 | Loki |
| `paperless.slice` | Slice `MemoryMax` 2G auf `system-paperless.slice` | `systemd.slices` |
| `paperless.service` | OOM +250 | web, scheduler, task-queue |
| `caddy { }` | 768M (OOM via critical-systemd) | Caddy |
| `pocketId { }` | 256M, OOM -900 | Pocket-ID |
| `vector { }` / `grafana { }` | 512M, OOM +200 | Observability |
| `arr { }` | 512M, OOM +200 | Sonarr/Radarr/Readarr/Prowlarr |

### Postgres-Formel (32 GB → 10G Max)

- `memoryMax` = `floor(ramGB × 0.3125)` GB (min. 4G) — deckt `shared_buffers` (25 %) + Overhead
- `memoryHigh` = `floor(ramGB × 0.25)` GB (min. 3G) — weiches Drosseln vor Hard-Kill

---

## 4. P1-Limits (implementiert)

| Dienst | MemoryMax | MemoryHigh | OOMScore | Datei |
|--------|-----------|------------|----------|-------|
| `postgresql` | ~10G @ 32GB RAM | ~8G | -800 | `modules/10-network.nix` |
| `jellyfin` | 6G | 4G | +100 | `modules/50-media/jellyfin.nix` |
| `sabnzbd` | 2G | 1536M | +300 | `modules/50-media/sabnzbd.nix` |
| `loki` | 1G | 768M | +300 | `modules/40-observability.nix` |
| `paperless-*` (Slice) | 2G gesamt | 1536M | +250 je Unit | `modules/60-apps/automation.nix` |

Paperless-Units in der Slice: `paperless-web`, `paperless-scheduler`, `paperless-task-queue`.

---

## 4b. P2-Limits (implementiert)

| Dienst | MemoryMax | MemoryHigh | OOMScore | Datei |
|--------|-----------|------------|----------|-------|
| `sonarr` / `radarr` / `readarr` / `prowlarr` | 512M | 384M | +200 | `modules/50-media/arr-helper.nix` |
| `caddy` | 768M | 512M | -900 (critical-systemd) | `modules/60-apps/default.nix` |
| `pocket-id` | 256M | 192M | -900 | `modules/10-network.nix` |
| `vector` | 512M | 384M | +200 | `modules/40-observability.nix` |
| `grafana` | 512M | 384M | +200 | `modules/40-observability.nix` |

### Was ist `arr-helper.nix`?

**Kein eigener Dienst** — eine Nix-Fabrik, die die vier *arr-Apps gleich aufbaut:

```
arr-stack.nix  →  arr-helper.mkArrService { name = "sonarr"; … }
              →  systemd + User + Sandboxing + Caddy + RAM-Limit
```

Ohne Helper müsste dasselbe fünfmal in `sonarr.nix`, `radarr.nix`, … stehen.

---

## 5. System-Baseline (nicht in memory-policy.nix)

| Komponente | Setting | Datei |
|------------|---------|-------|
| ZRAM | 25 % RAM, zstd, swappiness 180 | `modules/00-core.nix` |
| Blocky | Max 500M, OOM -1000 | `modules/10-network.nix` + `critical-systemd.nix` |
| Valkey | App `maxmemory 256mb` | `modules/10-network.nix` |
| Home Assistant | Max 2G, OOM +300 | `modules/60-apps/iot.nix` |
| Caddy | Max 768M, OOM -900 | `modules/60-apps/default.nix` |

---

## 6. Backlog (P3+)

| Prio | Dienst | Vorschlag |
|------|--------|-----------|
| P3 | nix-daemon | MemoryMax bei Builds |
| P3 | vaultwarden, n8n, forgejo | siehe AUDIT §11 Tier 5 |
| P4 | systemd-oomd | optional |

---

## 7. Verifikation

```bash
# Limits live
systemctl show postgresql jellyfin sabnzbd loki paperless-web \
  -p MemoryMax,MemoryHigh,MemoryCurrent,OOMScoreAdjust

# Paperless-Slice
systemctl show paperless.slice -p MemoryMax,MemoryCurrent

# cgroup-OOM / Kernel-OOM
journalctl -k -g 'oom|Out of memory' --since '7 days ago'
journalctl -u jellyfin -g 'killed|oom' --since '7 days ago'
```

Nach NixOS-Änderung:

```bash
nixos-rebuild build --flake .#q958
```

---

## 8. Regeln für KI-Änderungen

### NIEMALS (ohne User-Freigabe)

- `MemoryMax` von Tier-0-Diensten (blocky, sshd, tailscaled) entfernen oder auf `infinity` setzen
- Postgres `memoryMax` unter `shared_buffers` + 1G setzen
- Nur `OOMScoreAdjust` ohne `MemoryMax` bei bekannten RAM-Fressern (Jellyfin, SABnzbd, Loki, Paperless)

### IMMER

- Neue RAM-lastige Dienste über `memory-policy.nix` oder dokumentiertes Tier-Modell
- `hardware.ramGB` aus `profile.nix` für DB-Caps — keine Magic Numbers in Modulen
- Dieses Dokument + `AUDIT` §11 bei Architektur-Änderungen aktualisieren

---

## 9. Changelog

| Datum | Änderung |
|-------|----------|
| 2026-06-17 | P2: *arr, Caddy, Pocket-ID, Vector, Grafana |
| 2026-06-17 | `lib/memory-policy.nix` + P1-Limits (Postgres, Jellyfin, SABnzbd, Loki, Paperless) |
| 2026-06-17 | Initiales memory_oom.md |