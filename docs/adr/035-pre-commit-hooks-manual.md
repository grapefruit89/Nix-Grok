---
meta:
  role: doc
  purpose: ADR-035 Pre-commit Hooks — manuell installieren statt activationScript
  status: accepted
  date: 2026-07-10
  betrifft:
    - modules/00-core/09-nix-tools.nix
    - modules/00-core/README.md
    - docs/GUIDE-developer-experience.md
  tags:
    - adr
    - dx
    - pre-commit
    - layer-0
---

# ADR-035: Pre-commit Hooks — einmalig manuell statt activationScript {#adr-035}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-10 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

`09-nix-tools.nix` enthielt ein `system.activationScripts.preCommitInstall`-Block, der
nach jedem `nixos-rebuild switch` `pre-commit install` in `.git/hooks/` ausführte.

Probleme:

1. **Layer-0 soll production-neutral sein.** `activationScripts` laufen bei jedem
   Switch — auch auf einem hypothetischen Produktionsserver der kein `.git` hat.
   Der Block war mit `my.mode == "development"` gegated, aber das Prinzip gilt:
   Dev-Tooling gehört nicht in `modules/00-core/`.

2. **Root schreibt in User-Arbeitsverzeichnis.** `system.activationScripts` laufen
   als root. `.git/hooks/` ist ein Benutzer-Concern — ein Root-Prozess der darin
   schreibt ist architektonisch falsch.

3. **Redundant.** Git merkt sich Hooks dauerhaft in `.git/hooks/`. Nach einmaligem
   `pre-commit install` sind die Hooks persistent — kein erneutes Installieren nach
   Rebuilds nötig. Der Block hat praktisch nichts getan außer Lärm erzeugt.

4. **`|| true` maskiert Fehler.** Der Block schluckte Fehler lautlos — POL-FMT-Verletzungen
   bei der Hook-Installation wären unsichtbar gewesen.

## Entscheidung {#entscheidung}

`activationScripts.preCommitInstall` aus `09-nix-tools.nix` entfernt.

`pre-commit` bleibt als System-Package installiert (via `09-nix-tools.nix`).

### Einmaliger Setup-Schritt {#setup}

Nach Clone oder auf neuem System einmalig:

```bash
pre-commit install --config /etc/nixos/.pre-commit-config.yaml
```

Git merkt sich die Hooks. Kein erneuter Aufruf nach Rebuilds nötig.

### Hooks (`.pre-commit-config.yaml`) {#hooks}

| Hook | Blocking? | Zweck |
|------|-----------|-------|
| `nixfmt` | ja | RFC-Style Format (POL-FMT-010) |
| `statix` | nein | Linter; `repeated_keys` ist NixOS-Modul-Pattern, kein Fehler |
| `deadnix` | ja | Keine ungenutzten Bindings |

## Konsequenzen {#konsequenzen}

### Positiv

- Layer-0 (00-core) hat keine `activationScripts` mehr außer `05-creds.nix` (P0, geplant).
- `rg 'activationScripts' modules/00-core/` → nur 05-creds (expected).
- Kein Root-Prozess schreibt mehr in `.git/`.

### Negativ / Risiken

- Nach erstem Clone auf neuem System: Hooks fehlen bis `pre-commit install` ausgeführt wurde.
  Mitigation: Dokumentiert in README und GUIDE-developer-experience.md.
- Bei versehentlichem `git checkout --` auf `.git/hooks/`: Hooks weg. Gleiche Mitigation.

## Alternativen verworfen {#alternativen}

- **home-manager `home.activation`** — gleiches Problem eine Ebene tiefer: Shell als User
  in Aktivierungsskript; home-manager-Activation ist für persistent gemanagte Configs,
  nicht für einmalige Repo-Setup-Schritte.
- **`systemd.user` Timer** — drastisches Overkill für einen einmaligen `pre-commit install`.
- **Im activationScript belassen** — widerspricht Layer-0-Produktionsneutralität (ADR-032).

## Siehe auch {#siehe-auch}

- [ADR-012 — Moderne CLI-Tools](012-modern-cli-tools.md) — `pre-commit` als Teil des Dev-Toolings
- [ADR-032 — OS-Native First](032-os-native-first.md) — Layer-0 Produktionsneutralität
- [GUIDE-developer-experience.md](../GUIDE-developer-experience.md) — Setup-Anleitung
