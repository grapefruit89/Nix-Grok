---
meta:
  role: doc
  purpose: ADR-013 Flake-Portabilität — maximale Reproduzierbarkeit, minimale experimental-features
  status: accepted
  date: 2026-06-29
  betrifft:
    - modules/00-core/09-nix-tools.nix
    - flake.nix
    - flake.lock
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-flake-portability.md
    - docs/adr/007-dendritic-one-file-per-service.md
  tags:
    - adr
    - flakes
    - portability
    - reproducibility
    - nix
---

# ADR-013: Flake-Portabilität — maximale Reproduzierbarkeit ohne Experimente {#adr-013}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-29 |
| **Host** | q958 |

## Kontext {#kontext}

- Das System verwendet `nix-command` + `flakes` als experimental-features.
- `nix-command` und `flakes` sind de-facto Standard für Flake-basierte NixOS-Systeme.
- `auto-allocate-uids` und `cgroups` (ebenfalls experimental) wurden als unnötig entfernt.
- Externe Flake-Inputs von Fremd-Repos wurden bewusst nicht übernommen ([ADR-007](007-dendritic-one-file-per-service.md)).
- Frage: Kann in 2 Jahren aus den Nix-Dateien allein ein identisches System gebaut werden?

## Entscheidung {#entscheidung}

### Welche experimental-features bleiben {#experimental-features}

```nix
experimental-features = [ "nix-command" "flakes" ];
```nix

Nur diese zwei — sie sind alternativlos für dieses Setup. Alle anderen wurden entfernt.

### Warum Flakes besser als Channels sind {#flakes-vs-channels}

| | Channels (flakeless) | Flakes |
|---|---|---|
| Reproduzierbarkeit | Nein — "heute anderes nixpkgs als gestern" | Ja — exakter Commit in `flake.lock` |
| Neues System in 2 Jahren | Anderes Ergebnis | Identisch wenn `flake.lock` vorhanden |
| Offline-Betrieb | Kein Lockfile → unklar welches nixpkgs | `flake.lock` + Nix-Store = reproduzierbar |

### Portabilitätsstrategie {#portabilitaet}

**Tier 1 — Immer vorhanden (Git, kein Aufwand):**
- `flake.nix` + `flake.lock` im Repo committed → exakter Fingerabdruck aller Versionen
- `nixos-rebuild switch --flake /etc/nixos#q958` reproduziert das System exakt

**Tier 2 — Input-Archiv (einmal im Jahr, ~5 Minuten):**
```bash
# Alle Flake-Inputs lokal in den Nix-Store laden {#alle-flake-inputs-lokal-in-den-nix-store-laden}
nix flake archive
```

**Tier 3 — Vollständiges System-Snapshot (für echten Offline-Transport):**
```bash
# Komplette Closure exportieren {#komplette-closure-exportieren}
nix-store --export $(nix-store -qR /run/current-system) > /backup/nixos-closure.nar
# Auf neuem Rechner importieren: {#auf-neuem-rechner-importieren}
nix-store --import < /backup/nixos-closure.nar
```nix

### Risikobewertung externe Abhängigkeiten {#risiko}

| Abhängigkeit | Ausfallrisiko | Mitigation |
|---|---|---|
| `github.com/NixOS/nixpkgs` | sehr gering | `flake.lock` + lokaler Mirror |
| `cache.nixos.org` | gering | System baut lokal trotzdem |
| `nix-community.cachix.org` | mittel | System baut lokal trotzdem |

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- `flake.lock` im Git → jeder Rebuild ist deterministisch reproduzierbar.
- Neuer Rechner: `git clone` + `nixos-rebuild switch` → identisches System.
- Kein "dependency hell" — exakte Versionen für alles eingefroren.

### Negativ {#negativ}

- Flake-Inputs müssen gelegentlich aktualisiert werden (`nix flake update`).
- Erstbuild auf neuem System benötigt Internet (oder vorab-archivierte Inputs via Tier 2/3).
- `nix-command` + `flakes` bleiben offiziell "experimental" bis Nix 3.x stabilisiert.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Konfiguration | `modules/00-core/09-nix-tools.nix` → `nix.settings.experimental-features` |
| Lockfile | `flake.lock` (committed, niemals in .gitignore) |
| Portabilitäts-Guide | `docs/guides/GUIDE-flake-portability.md` |

## Alternativen verworfen {#alternativen}

- **Channels (flakeless)** — nicht reproduzierbar; "nixos-rebuild switch" heute ≠ morgen. Abgelehnt.
- **`auto-allocate-uids` experimental-feature** — kein Nutzen für Homelab, erhöht Komplexität. Entfernt.
- **Externe Flake-Inputs von Fremd-Repos** — Abhängigkeit auf externe Repos bricht Offline-Portabilität. Nicht übernommen ([ADR-007](007-dendritic-one-file-per-service.md)).

## Siehe auch {#siehe-auch}

- [ADR-007 — Dendritische Module](007-dendritic-one-file-per-service.md) — keine externen Flake-Inputs für Dienst-Module
- [GUIDE-flake-portability](../guides/GUIDE-flake-portability.md) — ausführliche Portabilitäts-Anleitung
