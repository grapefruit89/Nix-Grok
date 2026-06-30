# Session-Retrospektive: Repo-Analyse & Knowledge-Migration

**Datum:** 2026-06-30  
**Typ:** Repo-Audit + Knowledge-Migration  
**Repos analysiert:** mynixos (v1), mynixos-v5, mynixos-knowledge-base, nix-hermes

---

## Was analysiert wurde

Vier Vorgänger-Repos auf echte Lücken in Nix-Grok untersucht. Fokus: Was ist genuines Wissen,
was ist bereits vorhanden, was war KI-Halluzination?

---

## Überraschungen (positiv)

**Nix-Grok ist weiter als gedacht:**
- Dropbear Rescue SSH ist bereits implementiert (`20-security.nix`, aktiv ab Stufe 8)
- SQLite + MCP (`nixos_docs.sqlite`) existiert bereits — nix-hermes hatte das nie implementiert
- `forbidden-tech.nix` hatte Docker/Cron/Lanzaboote-Assertions bereits

**nix-hermes wurde von einer externen KI falsch beschrieben:**
- `build_db.js`, `nixos_docs.db`, `mcp_config.json` wurden als *implementiert* dargestellt
- In Wirklichkeit: `LLM_FIRST_INSTRUCTIONS.md` ist eine Bauanleitung die eine KI ausführen soll
- Nix-Grok ist mit `nixos_docs.sqlite` + FTS5 + eigenem MCP-Server deutlich weiter

---

## Echte Lücken gefunden

| Lücke | Schwere | Fix |
|-------|---------|-----|
| SOPS `sshKeyPaths` falsch für Impermanence | **Hoch** — hätte Stufe-9-Boot-Fail verursacht | Behoben in `05-sops.nix` |
| Kein No-GUI Build-Assert | Mittel — Headless-Policy nicht durchgesetzt | Behoben in `forbidden-tech.nix` |
| SSH Socket-Aktivierung nicht als ANTIPATTERN | Niedrig — Wissen fehlte, kein Code-Problem | Dokumentiert |
| Kein Anti-RAID ADR | Niedrig — gelebte Praxis, nicht dokumentiert | ADR-022 geschrieben |
| Kein learnings/-Ordner | Niedrig — fehlende Retrospektiv-Schicht | Dieser Ordner |

---

## Methodik-Erkenntnisse

**Was gut funktioniert hat:**
- Direkte Repo-Inspektion via GitHub API statt externer KI-Analyse vertrauen
- Parallel mehrere Key-Dateien fetchen (ADRs, service files, policy files)
- Zuerst checken ob etwas in Nix-Grok schon vorhanden ist bevor "Gap" ausgerufen wird

**Was schlecht funktioniert hat:**
- Externe KI-Analysen als Grundlage nehmen ohne eigene Verifikation — nix-hermes-Analyse war teilweise halluzniert
- Die knowledge-base hat ~150 Dateien; ohne Fokus-Filter werden wichtige Befunde von unwichtigen begraben

**Empfehlung für künftige Repo-Audits:**
1. GitHub API Tree first (Strukturübersicht)
2. Gezielt ADR-Nummern holen die thematisch passen
3. Immer in Nix-Grok gegenprüfen ob es das schon gibt
4. Erst implementieren wenn echter Gap bestätigt

---

## Generierte Artefakte

| Datei | Typ | Inhalt |
|-------|-----|--------|
| `docs/adr/021-sops-impermanence-boot-timing.md` | ADR | SOPS Race-Condition Fix |
| `docs/adr/022-no-raid-distance-parity.md` | ADR | Kein RAID — geografische Distanz |
| `docs/guides/ANTIPATTERNS.md` | Guide-Update | SSH Socket-Aktivierung Eintrag |
| `lib/forbidden-tech.nix` | Code | POL-FT-006/007/008 GUI-Assertions |
| `modules/00-core/05-sops.nix` | Code | SOPS sshKeyPaths + Ordering Fix |
| `docs/SOURCES.md` | Docs-Update | Repo-Genealogie Tabelle |
| `docs/learnings/FINDINGS-REGISTRY.md` | Learnings | Befund-Provenance-Registry |
| `docs/learnings/2026-06-30-repo-analysis.md` | Learnings | Diese Datei |

