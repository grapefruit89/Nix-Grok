---
meta:
  role: doc
  purpose: Repo-Einstieg — Schnellstart q958, Flake-Build
  docs:
    - AGENTS.md
    - docs/ROADMAP.md
  tags:
    - readme
---

# NixmitGROK

NixOS-Flake für den Fujitsu Q958 Homelab-Server. Architektur und Regeln: [`AGENTS.md`](AGENTS.md).

## Schnellstart (q958)

```bash
# 1. Secrets (einmalig, nicht committen)
cp machines/q958/profile.local.nix.example machines/q958/profile.local.nix
# passwordHash + devKeys ausfüllen

# 2. Config prüfen / bauen
nix build .#nixosConfigurations.q958.config.system.build.toplevel --impure

# 3. Auf dem Server aktivieren (sync /home/nixos → /etc/nixos + switch)
sudo tools/rebuild-q958.sh
```

Kanonischer Pfad auf q958: `/etc/nixos` — `configuration.nix` importiert nur `machines/q958/default.nix`.

## Rollout

Eine Zahl steuert alles: `machines/q958/profile.nix` → `rollout.stufe`

| Stufe | Inhalt |
|-------|--------|
| 0 | SSH, Netz, Grok CLI |
| 1 | zram, kernel-slim, boot-safeguard |
| 2 | Blocky, PostgreSQL, Valkey, Tailscale, Pocket-ID |
| 5 | Caddy |
| 6 | Media (*arr, Jellyfin, SAB, VPN) |
| 7 | Apps (Vaultwarden, HA, Forge, …) |
| 8 | nftables, CrowdSec, fail2ban |
| 9 | Impermanence / Production |

Nach Änderung: `sudo tools/rebuild-q958.sh`

Details: [`docs/ROADMAP.md`](docs/ROADMAP.md)

## Wichtige Pfade

| Pfad | Rolle |
|------|-------|
| `flake.nix` | Flake-Einstieg |
| `machines/q958/profile.nix` | Maschinenwerte (keine Secrets) |
| `machines/q958/profile.local.nix` | Secrets + Notfall-Passwort (**gitignored**) |
| `machines/q958/rollout.nix` | `.enable` nach Stufe |
| `users/moritz/profile.nix` | User, Domain, SSH-Keys |
| `modules/` | Generische Module |
| `lib/` | Helfer (Caddy, Kernel, VPN) |

## Secrets

- Dev: `profile.local.nix` + `machines/q958/secrets.nix` (Dateien unter `/var/lib/secrets`)
- Production: SOPS — geplant, noch nicht aktiv
- Vor Push: `tools/verify-no-secrets.sh`

## Domain

Aktuell: `nix.m7c5.de` (User-Profil). Cloudflare DNS + Fritzbox-DHCP siehe Roadmap — **noch manuell**.