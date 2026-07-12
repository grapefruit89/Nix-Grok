# AGENTS — STOP: Nicht versioniert

Dieses Verzeichnis liegt **außerhalb** des kanonischen Git-Repos **`/etc/nixos`**
(`github.com/grapefruit89/Nix-Grok`).

## Für KI-Agenten (Cursor, Grok, Claude, …)

**Alles, was ins Homelab-Repo gehört, wird nur unter `/etc/nixos/` bearbeitet.**

| Gehört ins Repo | Gehört **nicht** hierher |
|-----------------|--------------------------|
| `.nix`, `.sh`, `flake.nix`, Module | Kopien, `*.patch`, `disko-*.nix` |
| `docs/`, `scripts/`, `machines/` | Scratch-Dateien, „schnelle“ Entwürfe |
| Committbare Guides & ADRs | Arbeitsstände außerhalb von Git |

**Regel:** Vor jeder NixOS-Änderung: `cd /etc/nixos && git status`

Wenn du Dateien hier erstellt hast → **sofort nach `/etc/nixos` verschieben**, `git add`, committen.
**Nicht** hier lassen „bis später“.

## Ausnahmen (bewusst lokal)

- `secrets/` — echte Credentials, **niemals** committen
- Persönliche Notizen (`grok-*.md`, `WICHTIG-*.md`)
- Editor-Cache, `.cache/`, Build-`result`

## Siehe auch

- `/etc/nixos/AGENTS.md` — Projektregeln
- `/etc/nixos/docs/EMERGENCY-RECOVERY.md` — Notfall Recovery