---
meta:
  role: doc
  purpose: ADR-012 Moderne CLI-Tools — bat/eza/fd/rg systemweit, nh für Rebuilds
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - cli
    - dx
---

# ADR-012: Moderne CLI-Tools systemweit (bat, eza, fd, rg, nh, nvd)

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-28 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Das System wird intensiv interaktiv genutzt (SSH, Claude Code, Hermes-Agent).
- Klassische POSIX-Tools (`cat`, `ls`, `find`, `grep`, `top`, `du`, `df`) geben
  keinen Kontext, keine Farben, keine Git-Integration.
- KI-Agenten (Claude Code, Hermes) greifen auf Shell-Tools zurück; schlechter
  Output = schlechtere Entscheidungen.
- `nixos-rebuild` hat keine eingebaute Diff-Ausgabe — nach einem Switch ist nicht
  sofort klar, was sich geändert hat.

## Entscheidung

1. **Moderne Ersatz-Tools** werden via `environment.systemPackages` in `modules/00-core/01-core.nix`
   systemweit installiert:
   - `bat` statt `cat` — Syntax-Highlighting, Zeilennummern
   - `eza` statt `ls` — Icons, Git-Status, Farben
   - `fd` statt `find` — schneller, .gitignore-aware, intuitive Flags
   - `ripgrep` (`rg`) statt `grep` — deutlich schneller, .gitignore-aware
   - `btop` statt `top` — moderne UI, CPU/Speicher/Prozess-Übersicht
   - `dust` statt `du` — Baumansicht
   - `duf` statt `df` — schöner, farbiger Output
   - `nh` — UX-Wrapper um `nixos-rebuild` (menschliche Rebuilds)
   - `nvd` — Diff-Output nach jedem Switch

2. **Shell-Aliases** werden via `programs.bash.shellAliases` in `modules/00-core/01-core.nix`
   gesetzt. Aliases greifen **nur in interaktiven Bash-Sitzungen** (nicht in Systemskripten,
   Aktivierungsskripten oder `pkgs.writeShellScript`-Blöcken).

3. **Kein hartes Sperren** von alten Tools. Die POSIX-Binaries bleiben im System
   (NixOS-Abhängigkeiten brauchen sie). Aliases leiten interaktive Nutzung um.

4. **`nh` ersetzt NICHT den Dry-Build-Gate.** `scripts/nixos-rebuild-safe.sh` bleibt
   Pflicht vor jedem Commit (setzt das Flag, das der Gate prüft). `nh os switch` ist
   nur für komfortablere menschliche Rebuilds.

## Konsequenzen

### Positiv
- Interaktive Shell sofort besser: Git-Status in `ls`, Syntax-Highlighting bei Datei-Review.
- `nvd` nach jedem Switch zeigt genau, welche Pakete hinzu- oder weggefallen sind.
- KI-Agenten sehen besser strukturierten Output → weniger Fehlinterpretationen.
- `nh` spart Tipp-Arbeit bei manuellen Rebuilds.

### Negativ / Risiken
- Aliases können Skripte brechen, die `ls`/`cat` mit erwarteten Flags aufrufen
  → durch `program.bash.shellAliases` (nicht `environment.shellAliases`) nur in
  interaktiven Shells aktiv — Risiko minimal.
- `bat` ohne `--paging=never` öffnet einen Pager → Alias setzt das Flag explizit.

## Nicht entschieden

- **Funktion-Wrapper mit Warnung** (z. B. `cat()` gibt Fehler-Meldung): Abgelehnt,
  da NixOS-interne Skripte `cat` per POSIX aufrufen und eine Shell-Funktion in
  Subshells propagiert werden könnte.
- **`zoxide`** als `cd`-Ersatz: Optional, noch nicht installiert — Entscheidung offen.
- **`delta`** als `diff`-Ersatz: Sinnvoll für Git-Diffs, noch nicht installiert.

## Verknüpfte Entscheidungen

- [[ADR-011]]: Unified Port=UID=FolderPrefix — gleicher Commit-Kontext (DX-Verbesserungen)
