---
meta:
  role: doc
  purpose: ADR-013 Flake-Portabilität — maximale Reproduzierbarkeit ohne Experimente
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-flake-portability.md
  tags:
    - adr
    - flakes
    - portability
    - reproducibility
---

# ADR-013: Flake-Portabilität — maximale Reproduzierbarkeit ohne Experimente

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-29 |
| **Host** | q958 |

## Kontext

- Das System verwendet `nix-command` + `flakes` als experimental-features.
- `nix-command` und `flakes` sind zwar offiziell noch "experimental", aber de-facto Standard für
  jedes Flake-basierte NixOS-System — ohne sie funktioniert `nixos-rebuild switch --flake` nicht.
- `auto-allocate-uids` und `cgroups` (ebenfalls experimental) wurden als unnötig entfernt —
  kein Nutzen für ein 3-Personen-Homelab, erhöhen Komplexität ohne Gewinn.
- Frage: Kann in 2 Jahren aus den Nix-Dateien allein ein identisches System gebaut werden,
  auch wenn externe Quellen (GitHub, Cache) nicht mehr verfügbar sind?

## Entscheidung

### Welche experimental-features bleiben

```nix
experimental-features = [ "nix-command" "flakes" ];
```

Nur diese zwei — sie sind alternativlos für dieses Setup. Alle anderen wurden entfernt.

### Warum Flakes besser als Channels sind

Channels (das "alte" NixOS ohne Flakes) sind WENIGER portabel:

| | Channels (flakeless) | Flakes |
|---|---|---|
| Reproduzierbarkeit | Nein — "heute anderes nixpkgs als gestern" | Ja — exakter Commit in `flake.lock` |
| Neues System in 2 Jahren | Anderes Ergebnis | Identisch wenn `flake.lock` vorhanden |
| Offline-Betrieb | Kein Lockfile → unklar welches nixpkgs | `flake.lock` + Nix-Store = reproduzierbar |

### Portabilitätsstrategie

**Tier 1 — Immer vorhanden (Git, kein Aufwand):**
- `flake.nix` + `flake.lock` sind im Repo committed → exakter Fingerabdruck aller Versionen
- Alle Nix-Dateien unter `/etc/nixos/` → komplette Konfiguration
- `nixos-rebuild switch --flake /etc/nixos#q958` reproduziert das System exakt

**Tier 2 — Input-Archiv (einmal im Jahr, ~5 Minuten):**
```bash
# Alle Flake-Inputs (nixpkgs, home-manager, ...) lokal in den Nix-Store laden
nix flake archive
# Danach: alle Inputs als Store-Paths lokal vorhanden — kein Internet nötig für Rebuild
```

**Tier 3 — Vollständiges System-Snapshot (für echten Offline-Transport):**
```bash
# Komplette Closure exportieren (alle Store-Pfade des laufenden Systems)
nix-store --export $(nix-store -qR /run/current-system) > /backup/nixos-closure.nar
# Auf neuem Rechner importieren (kein Internet nötig):
nix-store --import < /backup/nixos-closure.nar
```

### Risikobewertung externe Abhängigkeiten

| Abhängigkeit | Ausfallrisiko | Konsequenz | Mitigation |
|---|---|---|---|
| `github.com/NixOS/nixpkgs` | sehr gering | Flake-Input nicht abrufbar | `flake.lock` + lokaler Mirror |
| `cache.nixos.org` | gering | längere Build-Zeiten | System baut trotzdem (lokal) |
| `nix-community.cachix.org` | mittel | längere Build-Zeiten | System baut trotzdem |

**nixpkgs-Commits verschwinden nicht.** Die NixOS Foundation betreibt Mirrors; alle Commits
seit 2012 sind verfügbar. Für einen 2-Jahres-Homelab-Horizont ist das kein reales Risiko.

## Konsequenzen

### Positiv

- `flake.lock` im Git → jeder Rebuild ist deterministisch reproduzierbar
- Neuer Rechner: `git clone` + `nixos-rebuild switch` → identisches System
- Kein "dependency hell" — exakte Versionen für alles eingefroren

### Negativ

- Flake-Inputs müssen gelegentlich aktualisiert werden (`nix flake update`)
- Erstbuild auf neuem System benötigt Internet (oder vorab-archivierte Inputs via Tier 2/3)
- `nix-command` + `flakes` bleiben offiziell "experimental" bis Nix 3.x stabilisiert

### Implementierung

| Artefakt | Pfad |
|----------|------|
| Konfiguration | `modules/00-core/01-core.nix` → `nix.settings.experimental-features` |
| Lockfile | `flake.lock` (committed, niemals in .gitignore) |
| Portabilitäts-Guide | `docs/guides/GUIDE-flake-portability.md` |
