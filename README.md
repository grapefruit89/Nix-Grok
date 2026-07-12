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

KI-Agenten: NixOS-Code **nur** unter `/etc/nixos` — [`docs/templates/AGENTS-outside-git.md`](docs/templates/AGENTS-outside-git.md).

---

## Notfall — disko-Unfall / q958 bootet nicht

> **2026-07-12:** `nix run github:nix-community/disko -- script` auf **laufendem** q958
> ausgeführt → ESP kaputt, ext4-Superblock beschädigt, **aber `/nix/store` + Generationen
> sehr wahrscheinlich noch auf der Platte.** Nicht rebooten bis Recovery durch ist.

**Vollständige Anleitung:** [`docs/EMERGENCY-RECOVERY.md`](docs/EMERGENCY-RECOVERY.md)

### Ein Befehl (NixOS Live-USB)

```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh | sudo bash
```

→ **`recover`** wählen (empfohlen): `e2fsck` + ESP + Bootloader → **gleiche Generationen**.

→ **`install`** nur wenn `recover` scheitert — **löscht alle Daten** auf sda.

### Verboten auf laufendem q958

```bash
nix run github:nix-community/disko -- script …   # NIEMALS — führt destroy/format aus
```

Sicher: `disko-q958.sh plan` (nur `--dry-run`, kein Schreiben). Details: [EMERGENCY-RECOVERY.md](docs/EMERGENCY-RECOVERY.md#guards--damit-das-nie-wieder-passiert).


## Kaltstart — curl ohne Secrets (neue Hardware)

Gleiche Config wie q958, Platzhalter-Secrets, externe Werte danach im **secrets-portal**:

```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/main/scripts/cold-start-q958.sh | sudo bash
```

Details: [`docs/guides/GUIDE-cold-start.md`](docs/guides/GUIDE-cold-start.md)


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
| 1 | zram, kernel-slim, nix-tuning |
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