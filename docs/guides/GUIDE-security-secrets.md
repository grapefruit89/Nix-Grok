---
meta:
  role: doc
  purpose: Betriebsguide Sovereign-Unlock, SSH-Härtung, Secrets
  docs:
    - docs/adr/010-production-ssh-impermanence.md
    - docs/SECURITY.md
    - modules/20-security.nix
  tags:
    - security
    - ssh
    - sops
---

# Security & Secrets Guide

> LUKS-Unlock, SSH Zero-Trust, Fail2ban↔nftables, Secrets-Pfad bis SOPS (Stufe 9).

## Modi

| Stufe | Modus | SSH | Root |
|-------|-------|-----|------|
| &lt; 9 | development | Port 22 (`profile.nix`) | normal |
| ≥ 9 | production | Port 53844 | tmpfs `/` + `/persist` binds |

Umschaltung: nur `machines/q958/profile.nix` → `rollout.stufe` erhöhen und rebuilden.

## SSH-Härtung (Production)

- Kein Passwort-Login, `MaxAuthTries = 3`
- **PermitTTY**: LAN/Tailscale → `yes`, sonst `no`
- Port aus `my.ports.ssh` (Rollout Stufe 9 → `productionSshPort`)

```bash
ssh -p 53844 moritz@100.64.0.1   # nach Stufe 9
```

## Sovereign Unlock

- LUKS-Gerät: `machines/q958/profile.nix` → `storage.luks.device`
- Initrd-SSH-Port: `security.sovereignUnlock.sshPort` (2222)
- QR-Fallback: `nms-qr-fallback` nach 30s ohne Mapper

## Secrets (aktuell)

Bis Stufe 9: `secrets-provision` → `/var/lib/secrets/*` (Tier A).  
Ab Stufe 9: `my.sops.enable` — Migration siehe [ADR-006](../adr/006-sops-migration-path.md).

## Hardened Core (Stufe 9 / Production)

`modules/27-hardened-core.nix` — nur mit `rollout.stufe >= 9`:

- Deaktiviert: ModemManager, udisks2, cups, bluetooth, wpa_supplicant, upower
- `security.hideProcessInformation = true`
- Maskiert: `plymouth-quit-wait`, `systemd-networkd-wait-online`
- **pcscd bleibt an** (YubiKey/LUKS)
- `lockKernelModules` default `false` — nur bei Bedarf aktivieren

## Kernel-Härtung (Stufe 8+)

`modules/26-kernel-hardening.nix` — aktiv ab Rollout Stufe 8:

- Sysctl: `kptr_restrict`, `ptrace_scope`, SYN-Cookies, Martian-Logging
- Boot: `init_on_alloc`, `slub_debug`, `mitigations=auto`
- Mounts: `/tmp`, `/dev/shm`, `/run/lock` mit `noexec,nosuid,nodev`
- **VPN:** `ip_forward` bleibt an, solange `vpn-confinement` aktiv ist

## Fail2ban

Mit aktiver nftables-Firewall: `banaction = nftables-f2b-set` — Bans landen im Set `f2b_blocked` (siehe [GUIDE-nftables-hardening](GUIDE-nftables-hardening.md)).

## Notfall

- Dropbear Rescue: Stufe 8+, Port 2222
- Notfall-User `nixos`: `machines/q958/profile.nix` → `access.emergency`