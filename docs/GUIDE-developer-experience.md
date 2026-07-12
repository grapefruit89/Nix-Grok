---
meta:
  role: doc
  purpose: Developer-Experience-Guide — nh, nvd, bat, eza, fd, rg und wie sie zusammenspielen
  docs:
    - docs/adr/012-modern-cli-tools.md
  tags:
    - guide
    - dx
    - cli
---

# GUIDE: Developer Experience auf q958

## Überblick

Alle modernen Tools sind systemweit installiert (via `modules/00-core/09-nix-tools.nix`).
Shell-Aliases sind für interaktive Bash-Sitzungen gesetzt — klassische POSIX-Befehle
rufen automatisch die moderneren Varianten auf.

## Setup einmalig (nach Clone) {#setup}

Nach jedem frischen Clone — einmalig ausführen:

```bash
pre-commit install --config /etc/nixos/.pre-commit-config.yaml
pre-commit install --hook-type pre-push --config /etc/nixos/.pre-commit-config.yaml
```

Git merkt sich die Hooks dauerhaft in `.git/hooks/`. Kein erneuter Aufruf nach
`nixos-rebuild switch` nötig (ADR-035).

Hygiene + Hooks:

| Schritt | Wann | Tool |
|---------|------|------|
| 1 | pre-commit | statix (info) |
| 2 | pre-commit | deadnix |
| 3 | pre-commit | nixfmt |
| 4 | pre-commit (bei `modules/`/`lib/`) | module-graph |

Verfügbare Hooks:

| Hook | Blocking | Zweck |
|------|----------|-------|
| `nixfmt` | ja | RFC-Style Format |
| `statix` | nein | Linter (repeated_keys = NixOS-Pattern, kein Fehler) |
| `deadnix` | ja | Keine ungenutzten Bindings |
| `module-graph` | ja (bei `modules/`/`lib/`) | Modul-Import-Graph → `docs/diagrams/*.mm` (NixoScope) |

Bei Änderungen in `modules/` oder `lib/` regeneriert der Hook die Diagramme automatisch — `git add docs/diagrams/` mit committen. Manuell: `ngraph`.


---

## Tägliche Rebuilds mit `nh`

```bash
# Rebuild + schöner Output (für menschliche Rebuilds)
nh os switch --flake /etc/nixos#q958

# Dry-run (zeigt was sich ändern würde, aber KEIN Dry-Build-Flag-Gate)
nh os dry --flake /etc/nixos#q958

# Nach dem Switch: Diff anzeigen was sich geändert hat
nvd diff /run/current-system result

# Oder nvd direkt nach nh (nh ruft nvd automatisch auf, wenn installiert)
nh os switch --flake /etc/nixos#q958
```

**Wichtig:** Der Dry-Build-Gate für Commits bleibt `sudo scripts/nixos-rebuild-safe.sh`.
`nh os dry` setzt das Flag NICHT — also vor jedem Commit weiterhin das Gate nutzen.

## Datei-Inspektion mit `bat`

```bash
# Datei mit Syntax-Highlighting lesen
bat /etc/nixos/modules/00-core/01-core.nix

# Ohne Pager (für Pipe-Nutzung)
bat --paging=never datei.nix

# Als `cat`-Alias (setzt --paging=never automatisch)
cat /etc/nixos/CLAUDE.md
```

## Verzeichnisse mit `eza`

```bash
# Basis (Alias ls)
ls /etc/nixos

# Long-Format mit Git-Status (Alias ll)
ll /etc/nixos/modules

# Baumansicht (Alias tree)
tree /etc/nixos/modules/00-core

# Mit versteckten Dateien
eza --icons --git -la --all
```

## Suchen mit `fd` und `rg`

```bash
# Alle .nix-Dateien im Repo finden (Alias find)
fd '\.nix$' /etc/nixos

# Text in allen .nix-Dateien suchen (Alias grep)
rg "technitium" /etc/nixos

# Mit Dateiname-Filter
rg "shellAliases" --type=nix /etc/nixos

# Exklusiv: fd respektiert .gitignore automatisch
fd 'profile.nix' /etc/nixos
```

## Disk-Übersicht mit `dust` und `duf`

```bash
# Verzeichnis-Größen anzeigen (Alias du)
dust /var/lib

# Partitions-Übersicht (Alias df)
duf

# Nur bestimmte Mounts
duf /var /nix
```

## System-Monitoring mit `btop`

```bash
# Interaktive UI (Alias top)
btop

# Einmalig (nicht interaktiv) — btop unterstützt kein One-Shot-Flag,
# für Skripte besser: ps aux | rg <prozess>
```

## Nix-spezifische Tools

```bash
# Abhängigkeiten eines Derivation visualisieren
nix-tree /nix/store/<hash>-<name>

# Paket-Größe-Diff zwischen zwei Systemgenerationen
nvd diff /nix/var/nix/profiles/system-1-link /run/current-system

# Build-Output überwachen (nom = nix-output-monitor)
nom build /etc/nixos#nixosConfigurations.q958.config.system.build.toplevel
```

## Shell-Alias-Übersicht

| Alias  | Expandiert zu            | Wozu |
|--------|--------------------------|------|
| `cat`  | `bat --paging=never`     | Datei-Inhalt mit Syntax-Highlighting |
| `ls`   | `eza --icons --git`      | Verzeichnis-Liste |
| `ll`   | `eza --icons --git -la`  | Long-Format-Liste |
| `tree` | `eza --tree --icons --git` | Baumansicht |
| `find` | `fd`                     | Datei-Suche |
| `grep` | `rg`                     | Text-Suche |
| `du`   | `dust`                   | Disk-Usage Baumansicht |
| `df`   | `duf`                    | Partitions-Übersicht |
| `top`  | `btop`                   | System-Monitor |

## Für Claude Code

Das Claude-Code-System-Prompt verbietet bereits `cat`/`head`/`tail` — stattdessen
`Read`/`Edit`/`Write`-Tools nutzen. Shell-Aliases haben keine Wirkung für Bash-Aufrufe
durch Claude Code (nur interaktive Shells). Der Vorteil der modernen Tools entsteht
hauptsächlich, wenn Claude Code via `Bash`-Tool interaktiv recherchiert und der Output
besser lesbar ist.

## Referenzen

- [ADR-012: Moderne CLI-Tools](adr/012-modern-cli-tools.md)
- [ADR-035: Pre-commit manuell](adr/035-pre-commit-hooks-manual.md)
- [bat Dokumentation](https://github.com/sharkdp/bat)
- [eza Dokumentation](https://github.com/eza-community/eza)
- [nh Dokumentation](https://github.com/viperML/nh)
