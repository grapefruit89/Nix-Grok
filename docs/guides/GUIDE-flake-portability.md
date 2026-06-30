---
meta:
  role: doc
  purpose: Flake-Portabilität — System auf neuem Rechner aufsetzen, Offline-Betrieb
  docs:
    - docs/adr/013-flake-portability.md
  tags:
    - guide
    - flakes
    - portability
    - disaster-recovery
---

# Guide: Flake-Portabilität & Reproduzierbarkeit {#guide-flake-portability}

> **Kurzversion:** `git clone` + `nixos-rebuild switch` → identisches System.
> Dieser Guide erklärt warum, und was zu tun ist wenn kein Internet vorhanden ist.

## Warum das System in 2 Jahren noch funktioniert {#warum}

Das System ist ein NixOS-Flake. Das bedeutet: in `flake.lock` steht der **exakte
Git-Commit-Hash** jeder externen Abhängigkeit (nixpkgs, home-manager, etc.).

```
flake.lock → "nixpkgs": { "rev": "abc123...", "url": "github:NixOS/nixpkgs" }
```

Solange dieser Commit auf GitHub (oder einem Mirror) existiert, baut `nixos-rebuild`
das **exakt gleiche System** — heute, in 2 Jahren, auf einem anderen Rechner.

## Szenario A: Neuer Rechner mit Internet {#szenario-a}

```bash
# 1. Minimal-NixOS booten (USB-Stick)
# 2. Repo klonen
git clone git@github.com:grapefruit89/Nix-Grok.git /etc/nixos

# 3. System bauen — identisch zum Original
nixos-rebuild switch --flake /etc/nixos#q958 --impure

# Fertig. Kein "welche Version war das?", kein Raten.
```

Die `flake.lock` ist der Fingerabdruck. Nie löschen, immer committen.

## Szenario B: Neuer Rechner, KEIN Internet (Tier-2-Archiv) {#szenario-b}

Einmal im Jahr auf dem laufenden System ausführen (5 Minuten):

```bash
# Alle Flake-Inputs in den lokalen Nix-Store laden
nix flake archive

# Prüfen welche Inputs jetzt lokal sind
nix flake metadata | grep "Inputs"
```

Danach alle Store-Pfade auf USB exportieren:

```bash
# Inputs identifizieren
INPUTS=$(nix flake archive --json 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  [print(v['path']) for v in d['inputs'].values()]")

# Auf USB exportieren
nix-store --export $INPUTS /nix/store/$(readlink /nix/var/nix/profiles/system) \
  | gzip > /media/usb/nixos-inputs.nar.gz
```

Auf dem neuen Rechner:
```bash
# Inputs importieren (kein Internet nötig)
gunzip -c /media/usb/nixos-inputs.nar.gz | nix-store --import

# Dann normal aufsetzen
nixos-rebuild switch --flake /etc/nixos#q958 --impure
```

## Szenario C: Komplettes System-Snapshot (Tier 3) {#szenario-c}

Für den Fall dass wirklich alles offline sein muss (kein nixpkgs-Download möglich):

```bash
# Komplette Closure des laufenden Systems exportieren
# (das ist alles was das System braucht — mehrere GB)
nix-store --export $(nix-store -qR /run/current-system) \
  | gzip > /backup/nixos-full-closure.nar.gz

echo "Größe:"
du -sh /backup/nixos-full-closure.nar.gz
```

Auf neuem Rechner:
```bash
# Importieren
gunzip -c /backup/nixos-full-closure.nar.gz | nix-store --import

# System aktivieren
/nix/store/<system-drv>/bin/switch-to-configuration switch
```

## Was nixpkgs-Commits über GitHub angeht {#nixpkgs-commits}

**Häufige Sorge:** "Was wenn GitHub verschwindet?"

**Realität:**
- nixpkgs-Commits auf GitHub existieren seit 2012 — kein einziger ist jemals verschwunden
- Die NixOS Foundation betreibt `https://releases.nixos.org` als Mirror
- `cache.nixos.org` (Hydra) hat Binary-Outputs für alle stabilen Commits
- Nix kann automatisch auf Mirrors zurückfallen

Für einen Homelab-Horizont von 2–5 Jahren ist das kein reales Risiko.

## Was IST ein reales Risiko {#reale-risiken}

| Risiko | Wahrscheinlichkeit | Konsequenz |
|---|---|---|
| `nix-community.cachix.org` fällt aus | mittel | Builds dauern länger, funktionieren |
| Eigene GitHub-Secrets verloren | mittel | Neues Repo, alte Config noch vorhanden |
| `flake.lock` nicht committed | hoch | Reproduzierbarkeit verloren |
| Hardware-Ausfall ohne Backup | hoch | Datenverlust, Config bleibt |

## Checkliste: Jahresroutine (5 Minuten) {#jahresroutine}

```bash
# 1. Inputs einfrieren (lokal cachen)
nix flake archive

# 2. Flake.lock committen (sollte immer der Fall sein)
git -C /etc/nixos status flake.lock

# 3. Generation-Übersicht
nixos-rebuild list-generations | tail -5

# 4. Alten Ballast entfernen
nix-collect-garbage --delete-older-than 30d
```

## Experimental-Features: Was bleibt, was nicht {#experimental-features}

```nix
# modules/00-core/01-core.nix
experimental-features = [
  "nix-command"   # neues CLI: "nix build", "nix develop" — alternativlos für Flakes
  "flakes"        # das flake.nix System — alternativlos für dieses Setup
  # "auto-allocate-uids"  # ENTFERNT: kein Nutzen, unnötige Komplexität
  # "cgroups"             # ENTFERNT: kein Nutzen für 3-Personen-Homelab
];
```

`nix-command` + `flakes` sind zwar offiziell "experimental" — aber seit Jahren die
einzige vernünftige Art NixOS zu betreiben. Sie werden nicht entfernt, nur irgendwann
offiziell stabilisiert.

## Siehe auch {#siehe-auch}

- [ADR-013 — Flake-Portabilität](../adr/013-flake-portability.md) — Entscheidung und Begründung
- [flake.lock](../../flake.lock) — der Fingerabdruck aller Versionen
- `nix flake metadata` — zeigt alle Inputs und ihre Commits
- `nix flake update` — aktualisiert alle Inputs auf aktuelle Versionen
