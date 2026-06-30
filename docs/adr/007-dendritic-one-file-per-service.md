---
meta:
  role: doc
  purpose: ADR-007 Dendritische Module — eine Datei pro Dienst, rollout.nix als einzige Enable-Quelle
  status: accepted
  date: 2026-06-17
  betrifft:
    - modules/50-media/
    - machines/q958/rollout.nix
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-dendritic-architecture.md
    - docs/adr/004-unix-socket-upstreams.md
    - docs/adr/005-critical-systemd-restart.md
    - docs/adr/011-unified-port-uid-schema.md
  tags:
    - adr
    - dendritic
    - module-struktur
    - rollout
---

# ADR-007: Dendritische Module — eine Datei pro Dienst {#adr-007}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Das Media-Stack-Monolith `arr-stack.nix` vermischte vier unabhängige Dienste.
- KB-Pattern „Pragmatic Dendritic Synthesis" empfiehlt: **eine Datei = ein Dienst**, `.enable` nur in `rollout.nix`.
- Sonarr und Radarr werden auf q958 **immer gemeinsam** genutzt — eine gemeinsame Datei ist pragmatischer als zwei Duplikate.
- Unix-Socket-Upstreams ([ADR-004](004-unix-socket-upstreams.md)) brauchen je eine Lib-Registrierung pro Dienst.
- Port/UID-Schema ([ADR-011](011-unified-port-uid-schema.md)) nutzt den Ordner-Präfix als Präfix-Basis.

## Entscheidung {#entscheidung}

1. **Media-Domain** (`modules/50-media/`):
   - `sonarr-radarr.nix` — Sonarr + Radarr zusammen (immer gemeinsam genutzt)
   - `readarr.nix`, `prowlarr.nix`, `sabnzbd.nix`, `jellyfin.nix` — je eigene Datei
   - `arr-helper.nix` bleibt Fabrik (kein zweites `mkArr`)
2. **`default.nix`** aggregiert nur Imports + zentrale `options` — keine Service-Config.
3. **Rollout** (`machines/q958/rollout.nix`) ist die einzige Quelle für `.enable`.
4. **Gelöscht:** `arr-stack.nix`.

### Modulstruktur-Konvention {#konvention}

```
modules/
  XX-layer/
    default.nix          ← nur imports + options
    dienst-a.nix         ← eine Datei pro Dienst
    dienst-b.nix
    helper.nix           ← gemeinsame Fabrik-Funktion (optional)
```

## Konsequenzen {#konsequenzen}

| Positiv | Negativ |
|---------|---------|
| Klare Ownership pro Dienst | Mehr Dateien in `50-media/` |
| Rollout-Stufen pro Dienst steuerbar | Sonarr/Radarr gekoppelt (gewollt) |
| KI/Review: eine Datei = ein PR-Thema | — |

## Alternativen verworfen {#alternativen}

- **Monolith `arr-stack.nix`** — Service-Config, Restart-Policy und Networking vermischt; KI und Review haben keinen klaren Scope. Abgelehnt (war bisheriger Zustand).
- **NIXMETA-Auto-Import** — Automatisches Einlesen von `*.nix`-Dateien ohne explizite Imports; erhöht Implizitheit. Nicht übernommen.
- **Flake-Inputs von Fremd-Repos** — Abhängigkeit auf externe Repos für Dienst-Module; schlechte Portabilität ([ADR-013](013-flake-portability.md)). Nicht übernommen.

## Siehe auch {#siehe-auch}

- [ADR-004 — Unix-Socket-Upstreams](004-unix-socket-upstreams.md) — Sockets werden pro Dienst-Datei registriert
- [ADR-005 — Restart=always](005-critical-systemd-restart.md) — `critical-systemd.nix` wird pro Datei eingebunden
- [ADR-011 — Port/UID-Schema](011-unified-port-uid-schema.md) — Ordner-Präfix `XX` als Basis für Port/UID-Nummerierung
- [ADR-013 — Flake-Portabilität](013-flake-portability.md) — keine externen Flake-Inputs für Dienst-Module
- [GUIDE-dendritic-architecture](../guides/GUIDE-dendritic-architecture.md) — ausführliche Erklärung des dendritischen Musters
