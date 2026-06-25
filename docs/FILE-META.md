---
meta:
  role: doc
  purpose: Spezifikation File-Meta-Header und Index-Tooling
  docs:
    - meta/schema.yaml
  tags:
    - meta
    - llm
---

# File-Meta — maschinenlesbare Datei-Header (zero Nix cost)

> **Schema:** `meta/schema.yaml` · **Index:** `meta/index.yaml` (generiert) · **Tool:** `tools/list-file-meta.sh`

## Idee

Metadaten leben **in Kommentaren** (`.nix`, `.sh`) oder als **Markdown-Frontmatter** (`.md`). Nix ignoriert Kommentare → **kein Eval-Overhead**, kein Import, keine Build-Zeit.

KI/LLM liest entweder die Datei direkt oder den aggregierten Index:

```bash
./tools/bootstrap-file-meta.py      # Header auf alle .nix + Guides setzen (idempotent)
./tools/list-file-meta.sh --write   # meta/index.yaml aktualisieren
./tools/list-file-meta.sh           # nach stdout
```

`bootstrap-file-meta.py` braucht einmalig `nix shell nixpkgs#python3`.

## Format für `.nix` / `.sh`

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Kurzbeschreibung in einem Satz
#   docs:
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - blocky
#   tags: [dns, network]
# ---
```

**ADR:** `docs/adr/NNN-thema.md` — Index in `docs/adr/README.md`. Nur existierende Pfade verlinken.

## Format für `.md`

```yaml
---
meta:
  role: doc
  purpose: …
  tags: [oom]
---
```

## Layer (AGENTS.md)

| layer | Pfad |
|-------|------|
| 1 | `flake.nix` |
| 2 | `machines/<host>/` |
| 3 | `modules/` |
| 4 | `users/` |
| 5 | `lib/` |

## Migration vom alten PURPOSE-Block

| Alt | Neu |
|-----|-----|
| `# PURPOSE` + Prosa | `meta.purpose` |
| `Key decisions -> ADR-…` (alt/tot) | `meta.docs` → `docs/adr/001-….md` |
| — | `meta.tags` für KI-Suche |

Alte `====` Banner können weg, sobald `meta:` steht.