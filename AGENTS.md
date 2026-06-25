---
meta:
  role: doc
  purpose: Projektregeln — 5-Schichten-Architektur, q958, Rollout, harte Regeln
  docs:
    - docs/FILE-META.md
  tags:
    - agents
    - architecture
---

# Projektregeln — /etc/nixos

## Architektur (5 Schichten)

| # | Pfad | Rolle |
|---|---|---|
| 1 | `flake.nix` | Einstieg, Inputs, Outputs |
| 2 | `machines/<host>/` | Maschine — Hardware, Netzwerk, Rollout |
| 3 | `users/<name>/` | Person — Keys, Domain, Home-Manager |
| 4 | `modules/` + `packages/` | Generische Fähigkeiten — leere/neutrale Defaults |
| 5 | `lib/` | Gemeinsame Helfer (z. B. Rollout) — `secrets/` kommt ganz zum Schluss |

## Trennung pro Host (`machines/<host>/`)

| Datei | Was gehört rein |
|---|---|
| `profile.nix` | IP, Hardware, Storage, Kernel, `rollout.stufe` — **nur Daten** |
| `default.nix` | Imports, `my.configs` — **reine Verdrahtung, keine `.enable`** |
| `access.nix` | Stufe 0+: Zugang (Netzwerk, Notfall-User, Assertions) |
| `rollout.nix` | Service-Aktivierung nach `rollout.stufe` |
| `hardware.nix` | Partitionen, Kernel-Module (liest `profile.nix`) |

## Trennung pro User (`users/<name>/`)

| Datei | Was gehört rein |
|---|---|
| `profile.nix` | SSH-Keys, Domain, Gruppen, Shell — alles **personenbezogen** |
| `default.nix` | System-User-Definition (liest `profile.nix`) |
| `home.nix` | Home-Manager / Dotfiles |

**Keine Magic Numbers.** Werte nur in den jeweiligen `profile.nix`.

## q958

- Maschine: `machines/q958/profile.nix`
- Betreiber: `users/moritz/profile.nix`
- Flake: `.#q958` → `machines/q958/default.nix`
- Rollout-Start: `rollout.stufe = 0` (Zugangsphase: SSH, Netz, Grok CLI)

### Storage-Tiers (harte Regeln)

| Tier | Bus / Medium | Labels (Ziel) | Rolle |
|---|---|---|---|
| A | **NVMe**-SSD, oder **SATA**-SSD wenn keine NVMe | `NIXBOOT`, `NIXPERSIST`, `NIXSTORE` | System-State, DB, Secrets |
| B | **SATA**-SSD only — nie NVMe, nie HDD | `NIXDATA`, `TIER_B_*` | Fast pool, Downloads-Cache |
| C | **HDD** only (spinning) | `NIXMEDIA`, `NIXBACKUP`, `TIER_C_*` | Cold storage / Media — Spindown |

**A/B: kein spinning device.** **B: immer SATA.** **C: immer HDD.**

q958: keine NVMe → `tierA.bus = sata` auf `/dev/sda`. Zusätzliche SATA-SSD wäre Tier B (`NIXDATA`). `mergerfsEnable` bleibt `false` bis Branches existieren.

## File-Meta (KI)

Maschinenlesbare Datei-Header **ohne Nix-Build-Kosten**: kommentiertes YAML in `.nix`/`.sh`, Frontmatter in `.md`.  
Schema: `meta/schema.yaml` · Bootstrap: `tools/bootstrap-file-meta.py` · Index: `tools/list-file-meta.sh --write` → `meta/index.yaml` · Doku: `docs/FILE-META.md` · **ADR:** `docs/adr/README.md`

## Harte Regeln

- Notfall-User `nixos` → `machines/q958/profile.nix` unter `access.emergency` (Maschinen-Zugang, kein users/-Eintrag)
- SOPS erst ganz am Ende
- Services schrittweise: `machines/q958/profile.nix` → `rollout.stufe` erhöhen, rebuild, testen
- **Eine Wahrheit für `.enable`:** nur `rollout.nix`, nie in `default.nix` — Ausnahme: `grok` immer an (Headless-Dev)
- **Module:** `user`, `domain`, `lanIP`, `tailscaleIP`, `ramGB` ohne Default — nur via `machines/` + `users/` setzen
- **Externe Integrationen** (AMT, Agent Zero, Zigbee): `machines/<host>/profile.nix` → `integrations` / `iot`