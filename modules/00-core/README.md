---
meta:
  role: doc
  purpose: README für modules/00-core — Schicht-0-Module (Fundament)
  tags:
    - readme
    - 00-core
---

# modules/00-core — Schicht 0: Fundament

Layer 0 — Systembasis, die **immer** aktiv ist (keine `rollout.stufe`-Gating).
Alle anderen Schichten (`10-network`, `50-media`, …) setzen diese voraus.

## Dateien

| Datei | Zweck |
|-------|-------|
| `01-core.nix` | **Haupt-Modul**: NixOS-Optionen (`my.*`), system-Packages, Shell-Aliases, Nix-Tuning, ZRAM, Boot-Safeguard, Locale, pre-commit-Hooks |
| `02-nixmeta-ban.nix` | Verbot von `# !type`-NIXMETA-Annotationen (statische Assertion) |
| `03-uid-registry.nix` | Unified UID=Port=FolderPrefix — zentrale UID-Vergabe (ADR-011) |
| `04-services-spec.nix` | Service-Spec-Matrix: Ports, Zonen, Subdomains (SSoT für Caddy + DNS) |
| `05-sops.nix` | SOPS-Stub (Stufe 9+, noch nicht aktiv) |
| `06-boot-watchdog.nix` | Boot-Watchdog: Panic bei Kernel-Oops / Soft-Lockup |
| `07-structure-validation.nix` | Strukturvalidierung: Port-Duplikate, Layer-Konsistenz |
| `default.nix` | Import aller 00-core-Module |

## Wichtige Optionen (Auszug)

```nix
my.mode = "development" | "production";     # Steuert Hardening-Level
my.configs.identity.domain = "…";           # Domain (aus users/moritz/profile.nix)
my.configs.identity.user = "moritz";
my.ports.<service> = <port>;                 # Zentrale Port-Registry
my.services.<name>.enable = true | false;   # Dienste-Toggle (via rollout.nix)
my.core.nix-tuning.enable = erstAb 1;
my.core.zram-swap.enable = erstAb 1;
my.core.boot-safeguard.enable = erstAb 1;
```

## System-Packages (01-core.nix)

### Nix-Toolchain
- `nixfmt` — Pflicht-Formatter (Pre-commit-Gate, POL-FMT-010)
- `statix` — Linter (informational)
- `deadnix` — Toter-Code-Detektor (blocking)
- `pre-commit` — Hook-Manager
- `nix-output-monitor` (nom) — Build-Output-Visualisierung
- `nix-tree` — Dependency-Graph-Visualisierung
- `nix-diff` — Derivation-Vergleich
- `cachix` — Binary-Cache-Client

### Moderne CLI-Tools (ADR-012)
- `nh` — `nixos-rebuild`-UX-Wrapper (menschliche Rebuilds)
- `nvd` — Diff-Output nach Switch
- `bat` → `cat` | `eza` → `ls` | `fd` → `find` | `ripgrep` → `grep`
- `btop` → `top` | `dust` → `du` | `duf` → `df`

## Shell-Aliases

Gesetzt via `programs.bash.shellAliases` — nur interaktive Bash-Sitzungen,
**kein Eingriff in Systemskripte oder Aktivierungsskripte**.

Vollständige Liste: [GUIDE-developer-experience.md](../GUIDE-developer-experience.md)

## Pre-commit-Hooks

Nach jedem `nixos-rebuild switch` werden die Pre-commit-Hooks via
`system.activationScripts.preCommitInstall` automatisch in `.git/hooks/` installiert.
Konfiguration: `/etc/nixos/.pre-commit-config.yaml`.

Hooks (in Reihenfolge):
1. `nixfmt` (blocking) — RFC-Style-Format
2. `statix` (informational) — `repeated_keys` ist NixOS-Modul-Pattern, kein Fehler
3. `deadnix` (blocking) — keine ungenutzten Bindings

## Referenzen

- [ADR-011: Unified Port=UID=FolderPrefix](../docs/adr/011-unified-port-uid-schema.md)
- [ADR-012: Moderne CLI-Tools](../docs/adr/012-modern-cli-tools.md)
- [GUIDE-developer-experience.md](../docs/GUIDE-developer-experience.md)
- [AGENTS.md](../AGENTS.md) — Architektur-Verfassung (6-Schichten-Modell)
