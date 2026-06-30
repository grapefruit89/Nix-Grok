---
meta:
  role: doc
  purpose: ADR-012 Moderne CLI-Tools systemweit — bat/eza/fd/rg/btop/nh/nvd für bessere DX
  status: accepted
  date: 2026-06-28
  betrifft:
    - modules/00-core/01-core.nix
  docs:
    - docs/adr/README.md
    - docs/adr/011-unified-port-uid-schema.md
  tags:
    - adr
    - cli
    - dx
    - shell
---

# ADR-012: Moderne CLI-Tools systemweit (bat, eza, fd, rg, nh, nvd) {#adr-012}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-28 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Das System wird intensiv interaktiv genutzt (SSH, Claude Code, Hermes-Agent).
- Klassische POSIX-Tools (`cat`, `ls`, `find`, `grep`, `top`, `du`, `df`) geben
  keinen Kontext, keine Farben, keine Git-Integration.
- KI-Agenten (Claude Code, Hermes) greifen auf Shell-Tools zurück; schlechter
  Output = schlechtere Entscheidungen.
- `nixos-rebuild` hat keine eingebaute Diff-Ausgabe — nach einem Switch ist nicht
  sofort klar, was sich geändert hat.
- Gleicher Commit-Kontext wie [ADR-011](011-unified-port-uid-schema.md) (DX-Verbesserungen Stufe 6).

## Entscheidung {#entscheidung}

### Installierte Tools {#tools}

1. **Moderne Ersatz-Tools** via `environment.systemPackages` in `modules/00-core/01-core.nix`:

   | Neues Tool | Ersetzt | Vorteil |
   |-----------|---------|---------|
   | `bat` | `cat` | Syntax-Highlighting, Zeilennummern |
   | `eza` | `ls` | Icons, Git-Status, Farben |
   | `fd` | `find` | schneller, .gitignore-aware |
   | `ripgrep` (`rg`) | `grep` | deutlich schneller, .gitignore-aware |
   | `btop` | `top` | moderne UI, CPU/Speicher/Prozess |
   | `dust` | `du` | Baumansicht |
   | `duf` | `df` | farbiger Output |
   | `nh` | `nixos-rebuild` | UX-Wrapper für menschliche Rebuilds |
   | `nvd` | — | Diff-Output nach jedem Switch |

2. **Shell-Aliases** via `programs.bash.shellAliases` in `modules/00-core/01-core.nix`.
   Aliases greifen **nur in interaktiven Bash-Sitzungen** (nicht in Systemskripten,
   Aktivierungsskripten oder `pkgs.writeShellScript`-Blöcken).

3. **Kein hartes Sperren** von alten Tools — POSIX-Binaries bleiben im System
   (NixOS-Abhängigkeiten brauchen sie). Aliases leiten nur interaktive Nutzung um.

4. **`nh` ersetzt NICHT den Dry-Build-Gate.** `scripts/nixos-rebuild-safe.sh` bleibt
   Pflicht vor jedem Commit. `nh os switch` ist nur für komfortablere menschliche Rebuilds.

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Interaktive Shell sofort besser: Git-Status in `ls`, Syntax-Highlighting bei Datei-Review.
- `nvd` nach jedem Switch zeigt genau, welche Pakete hinzu- oder weggefallen sind.
- KI-Agenten sehen besser strukturierten Output → weniger Fehlinterpretationen.
- `nh` spart Tipp-Arbeit bei manuellen Rebuilds.

### Negativ / Risiken {#negativ}

- Aliases können Skripte brechen, die `ls`/`cat` mit erwarteten Flags aufrufen
  → durch `programs.bash.shellAliases` (nicht `environment.shellAliases`) nur in
  interaktiven Shells aktiv — Risiko minimal.
- `bat` ohne `--paging=never` öffnet einen Pager → Alias setzt das Flag explizit.

## Alternativen verworfen {#alternativen}

- **Funktion-Wrapper mit Warnung** (z. B. `cat()` gibt Fehlermeldung): NixOS-interne Skripte rufen `cat` per POSIX auf; Shell-Funktion propagiert in Subshells. Abgelehnt.
- **`zoxide`** als `cd`-Ersatz: Optional, noch nicht installiert — Entscheidung offen.
- **`delta`** als `diff`-Ersatz: Sinnvoll für Git-Diffs, noch nicht installiert — Entscheidung offen.

## Siehe auch {#siehe-auch}

- [ADR-011 — Port/UID-Schema](011-unified-port-uid-schema.md) — gleicher DX-Commit-Kontext (Stufe 6)
- [ANTIPATTERNS.md#bastelmodus](../guides/ANTIPATTERNS.md#bastelmodus) — Bastelmodus (imperative Overrides) als häufigster Antipattern
