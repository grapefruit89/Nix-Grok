---
meta:
  role: doc
  purpose: ADR-007 Dendritische Module — eine Datei pro Dienst
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-dendritic-architecture.md
  tags:
    - adr
    - dendritic
---

# ADR-007: Dendritische Module — eine Datei pro Dienst

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Das Media-Stack-Monolith `arr-stack.nix` vermischte vier unabhängige Dienste.
- KB-Pattern „Pragmatic Dendritic Synthesis“ empfiehlt: **eine Datei = ein Dienst**, `.enable` nur in `rollout.nix`.
- Sonarr und Radarr werden auf q958 **immer gemeinsam** genutzt — eine gemeinsame Datei ist pragmatischer als zwei Duplikate.
- **Nicht** übernommen: NIXMETA-Auto-Import, flake-inputs von Fremd-Repos.

## Entscheidung

1. **Media-Domain** (`modules/50-media/`):
   - `sonarr-radarr.nix` — Sonarr + Radarr zusammen
   - `readarr.nix`, `prowlarr.nix`, `sabnzbd.nix`, `jellyfin.nix` — je eigene Datei
   - `arr-helper.nix` bleibt Fabrik (kein zweites `mkArr`)
2. **`default.nix`** aggregiert nur Imports + zentrale `options` — keine Service-Config.
3. **Rollout** (`machines/q958/rollout.nix`) ist die einzige Quelle für `.enable`.
4. **Gelöscht:** `arr-stack.nix`.

## Konsequenzen

| Positiv | Negativ |
|---------|---------|
| Klare Ownership pro Dienst | Mehr Dateien in `50-media/` |
| Rollout-Stufen pro Dienst steuerbar | Sonarr/Radarr gekoppelt (gewollt) |
| KI/Review: eine Datei = ein PR-Thema | — |

## Verknüpfung

```nix
# meta.docs in modules/50-media/sonarr-radarr.nix
#   - docs/adr/007-dendritic-one-file-per-service.md
```