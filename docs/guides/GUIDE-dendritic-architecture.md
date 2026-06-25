---
meta:
  role: doc
  purpose: Guide — dendritische Modul-Architektur
  docs:
    - docs/adr/007-dendritic-one-file-per-service.md
    - AGENTS.md
  tags:
    - guide
    - dendritic
---

# Guide: Dendritische Architektur

> **Prinzip:** Eine Datei = ein Dienst (oder eine fest gekoppelte Dienstgruppe).  
> **Quelle:** KB `GUIDE-Pragmatic-Dendritic-Synthesis` — ohne NIXMETA/Auto-Import.

## Regeln (q958)

| Was | Wo |
|-----|-----|
| `.enable` | nur `machines/q958/rollout.nix` |
| Maschinenwerte | `machines/q958/profile.nix` |
| Verdrahtung | `machines/q958/default.nix` (kein `.enable`) |
| Service-Logik | `modules/<domain>/<dienst>.nix` |
| Gemeinsame Helfer | `lib/` oder `*-helper.nix` |

## Media-Stack (50-media)

```
modules/50-media/
├── default.nix          # imports + options
├── arr-helper.nix       # Fabrik (mkArrService)
├── sonarr-radarr.nix    # Sonarr + Radarr (immer zusammen)
├── readarr.nix
├── prowlarr.nix         # VPN-NetNS
├── sabnzbd.nix
├── jellyfin.nix
├── audiobookshelf.nix
└── sync.nix
```

**Ausnahme Sonarr/Radarr:** Betreiber nutzt beide immer — eine Datei reduziert Duplikat ohne Kopplung zu verstecken.

## Neuer Dienst — Checkliste

1. `modules/<domain>/mein-dienst.nix` anlegen (mit `meta:`-Header)
2. `options.my.services.mein-dienst.enable` in `default.nix` der Domain
3. Import in `default.nix`
4. `machines/q958/rollout.nix` → `erstAb N`
5. Ports/UIDs in `profile.nix` / `lib/uid-registry.nix` wenn nötig
6. ADR nur bei architekturrelevanten Entscheidungen

## Was wir nicht machen

- Flake-inputs für fremde Media/VPN-Repos
- Recyclarr
- Monolith-Stacks (`arr-stack.nix` — entfernt)
- `.enable` in `default.nix` (Ausnahme: `grok` Headless-Dev)