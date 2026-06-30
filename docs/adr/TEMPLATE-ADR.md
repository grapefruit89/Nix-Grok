---
meta:
  role: template
  purpose: "Vorlage für neue ADRs — kopieren, NNN ersetzen, Platzhalter füllen"
  status: template
  date: YYYY-MM-DD
  # ─── PFLICHTFELDER FÜR ALERT-SCRIPT + KI-TRIAGE ─────────────────────────
  error_pattern: "regex der direkt auf journalctl-output passt"
  # Beispiele:
  #   "oom-kill.*\\.service"
  #   "strconv\\.Atoi.*invalid syntax"
  #   "Failed to load environment files"
  #   "cannot change owner.*not permitted"
  quick_fix: "Einzeiler-Fix (kopierbar, ohne Kontext)"
  services: [service-a, service-b]   # betroffene systemd-Units
  # ─── OPTIONAL ABER EMPFOHLEN ─────────────────────────────────────────────
  betrifft:                          # geänderte Dateien
    - lib/example.nix
    - modules/XX-layer/foo.nix
  docs:                              # verlinkte Dokumente (maschinenlesbar)
    - docs/adr/README.md
    - docs/adr/NNN-verwandte-entscheidung.md
    - docs/RUNBOOK.md
  tags:
    - adr
    - thema-a
    - thema-b
---

<!--
  ANLEITUNG — Diese Kommentare im fertigen ADR entfernen!

  DATEINAME:  NNN-kurzes-thema.md   (NNN = nächste freie Nummer)
  SPEICHERN:  docs/adr/NNN-kurzes-thema.md
  NACHHER:    sudo bash /etc/nixos/scripts/gen-toc.sh   (TOC aktualisieren)
              docs/adr/README.md Index-Tabelle ergänzen
              docs/RUNBOOK.md Schnellreferenz-Zeile ergänzen

  CROSS-LINK-SYNTAX:
    Gleiche Datei:        [→ Abschnitt](#anker-id)
    Andere ADR:           [ADR-NNN — Titel](NNN-datei.md)
    ADR mit Abschnitt:    [ADR-NNN Diagnose](NNN-datei.md#diagnose)
    Runbook:              [RUNBOOK — Service](../RUNBOOK.md#service)
    Guide:                [GUIDE-foo](../guides/GUIDE-foo.md#abschnitt)
    memory_oom:           [memory_oom.md](../memory_oom.md)

  ANKER-SYNTAX:
    ## Mein Abschnitt {#mein-abschnitt}
    Explizit → stabiler als Auto-Anker! Auto: "Mein Abschnitt" → #mein-abschnitt
    Sonderzeichen im Auto-Anker: ä→ä, ö→ö (GFM behält Umlaute, strip-only [^a-z0-9-])
    Explizit = sicher. Bei jedem h2/h3 verwenden.
-->

# ADR-NNN: Titel der Entscheidung {#adr-nnn}

<!--
  STATUS-TABELLE: Kompakte Metadaten für den Schnellüberblick.
  Status-Werte: proposed | accepted | deprecated | superseded
  Bei superseded: "superseded by [ADR-NNN](NNN-datei.md)" ergänzen.
-->

| Feld | Wert |
|------|------|
| **Status** | proposed |
| **Datum** | YYYY-MM-DD |
| **Host** | q958 |

---

## Kontext {#kontext}

<!--
  Was war das Problem / der Auslöser?
  - Stichpunkte, nicht Prosa
  - Links zu verwandten ADRs: "...braucht statische UIDs ([ADR-008](008-nftables.md))"
  - Fehler/Symptome die zum Problem geführt haben
-->

- Problem A — wie es sich manifestierte
- Problem B — Bezug zu [ADR-NNN](NNN-verwandte.md) (wenn relevant)
- Constraint C — warum naheliegende Lösung X nicht funktioniert

## Entscheidung {#entscheidung}

<!--
  Was wurde beschlossen? Kopierbare Befehle oder Nix-Snippets.
  Unterabschnitte mit {#anker} für Querverweise auf Teilentscheidungen.
-->

**Kernaussage der Entscheidung in einem Satz.**

### Teilentscheidung A {#teilentscheidung-a}

```nix
# Beispiel NixOS-Config
services.foo.enable = true;
```

### Teilentscheidung B {#teilentscheidung-b}

```bash
# Beispiel Shell-Befehl
sudo systemctl status foo
```

## Diagnose {#diagnose}

<!--
  PFLICHT wenn error_pattern gesetzt ist.
  Symptom + Befehle + erwarteter Output.
  KIs und das Alert-Script suchen hier den Match zu error_pattern.
-->

**Symptom:** Kurze Beschreibung was der Nutzer/Admin sieht.

```bash
# Hauptdiagnose-Befehl
journalctl -u <service> -n 20 --no-pager | grep -iE "error|fail"
```

**Erwarteter Output:**
```
<service>[1234]: Error: genauer Fehlertext der zum error_pattern passt
```

<details>
<summary>Vollständige Diagnose-Befehle (ausklappen)</summary>

```bash
# Alle Logs des Service
journalctl -u <service> --since '1 hour ago' --no-pager

# Service-Status
systemctl status <service> --no-pager

# Weitere spezifische Diagnose
```

</details>

## Fix {#fix}

<!--
  PFLICHT wenn error_pattern gesetzt ist.
  Jeder Befehl muss direkt kopierbar sein — kein Pseudocode.
  Nummeriert für Schritt-für-Schritt-Ausführung durch KI.
-->

```bash
# Schritt 1: Vorbedingung prüfen
systemctl status <service> --no-pager

# Schritt 2: Fix anwenden
# [konkreter Befehl]

# Schritt 3: Dry-build (immer vor switch!)
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# Schritt 4: Switch in tmux
# tmux new-session 'sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure 2>&1 | tee /tmp/nixos-switch.log; read'

# Schritt 5: Verifikation
systemctl status <service>
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Vorteil A
- Vorteil B — mit Link wenn ein anderer ADR profitiert: ([ADR-005](005-critical-systemd-restart.md))

### Negativ / Trade-offs {#negativ}

- Nachteil A
- Einschränkung B

### Implementierung {#implementierung}

<!--
  Tabelle der geänderten Dateien + Artefakte.
  Links wo sinnvoll.
-->

| Artefakt | Pfad |
|----------|------|
| Hauptconfig | `modules/XX-layer/foo.nix` |
| Hilfsbibliothek | `lib/bar.nix` |

### Verifikation {#verifikation}

```bash
# Befehl der beweist dass die Entscheidung korrekt implementiert ist
systemctl show <service> -p RelevantProperty
```

## Alternativen verworfen {#alternativen}

<!--
  Was wurde erwogen aber abgelehnt, und warum?
  Wichtig für KIs: verhindert dass die Alternative beim nächsten Mal wieder vorgeschlagen wird.
-->

- **Alternative A** — kurze Begründung warum nicht. Abgelehnt.
- **Alternative B** — Constraint der sie ausschließt. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| YYYY-MM-DD | Initial |

## Siehe auch {#siehe-auch}

<!--
  PFLICHT: Mindestens 1 Cross-Link.
  Format: [ADR-NNN — Titel](NNN-datei.md) — ein Satz warum der Link relevant ist
  Verwandte ADRs bidirektional verlinken (dort auch diesen ADR eintragen)!
-->

- [ADR-NNN — Verwandter Titel](NNN-verwandte.md) — warum relevant
- [RUNBOOK — Service](../RUNBOOK.md#service) — Quick-Fix bei Betriebsproblemen
- [docs/memory_oom.md](../memory_oom.md) — wenn RAM-relevant

---

> **Markdown-Referenz:** Alle Features (Anker, Mermaid, Collapsible, Cross-Links) → [CLAUDE-GUIDE.md](CLAUDE-GUIDE.md)
