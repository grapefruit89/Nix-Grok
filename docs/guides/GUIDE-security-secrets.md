---
meta:
  role: doc
  purpose: Betriebsguide Sovereign-Unlock, SSH-Härtung, Secrets
  docs:
    - docs/adr/010-production-ssh-impermanence.md
    - docs/adr/024-systemd-creds-tpm.md
    - docs/SECURITY.md
    - modules/20-security.nix
  tags:
    - security
    - ssh
    - systemd-creds
    - secrets
---

# Security & Secrets Guide {#guide-security}

> LUKS-Unlock, SSH Zero-Trust, Fail2ban↔nftables, Secrets via systemd-creds (Stufe 9).

## Modi {#modi}

| Stufe | Modus | SSH | Root |
|-------|-------|-----|------|
| &lt; 9 | development | Port 22 (`profile.nix`) | normal |
| ≥ 9 | production | Port 53844 | tmpfs `/` + `/persist` binds |

Umschaltung: nur `machines/q958/profile.nix` → `rollout.stufe` erhöhen und rebuilden ([ADR-010](../adr/010-production-ssh-impermanence.md)).

## SSH-Härtung (Production) {#ssh-haertung}

- Kein Passwort-Login, `MaxAuthTries = 3`
- **PermitTTY**: LAN/Tailscale → `yes`, sonst `no`
- Port aus `my.ports.ssh` (Rollout Stufe 9 → `productionSshPort`)

```bash
ssh -p 53844 moritz@100.64.0.1   # nach Stufe 9
```

## Sovereign Unlock {#sovereign-unlock}

- LUKS-Gerät: `machines/q958/profile.nix` → `storage.luks.device`
- Initrd-SSH-Port: `security.sovereignUnlock.sshPort` (2222)
- QR-Fallback: `nms-qr-fallback` nach 30s ohne Mapper

## Secrets {#secrets}

### Dev (Stufe < 9): secrets-provision {#secrets-dev}

`profile.local.nix` → Activation Script → `/var/lib/secrets/*`

Gitignored, nur auf der Maschine, keine Verschlüsselung nötig (Dev-Werte).

### Production (Stufe 9+): systemd-creds {#secrets-prod}

`my.creds.enable = true` → `LoadCredentialEncrypted=` in Service-Units → `$CREDENTIALS_DIRECTORY/<name>`

Kein Flake-Input, kein Age-Key auf Disk, automatisches Cleanup durch systemd.
Vollständige Strategie: [ADR-024 — systemd-creds + TPM2](../adr/024-systemd-creds-tpm.md).

#### Credential versiegeln (einmalig pro Secret)

```bash
# Ohne TPM (host key — Default):
printf '%s' 'WERT' | systemd-creds encrypt \
  --name=sonarr_api_key - /var/lib/credstore.encrypted/sonarr_api_key.cred

# Mit TPM (nach my.creds.useTpm = true):
printf '%s' 'WERT' | systemd-creds encrypt --with-key=tpm2 \
  --name=sonarr_api_key - /var/lib/credstore.encrypted/sonarr_api_key.cred
```

#### TPM-Migration: ein Boolean-Flip

```nix
# In rollout.nix — mehr ist nicht nötig:
my.creds.useTpm = true;  # war: false
```

Danach alle Credentials neu versiegeln (einmalig), rebuild.

#### In Service-Units nutzen

```nix
systemd.services.sonarr.serviceConfig = {
  LoadCredentialEncrypted =
    "sonarr_api_key:${config.my.creds.storeDir}/sonarr_api_key.cred";
};
# Im Service-Script: $CREDENTIALS_DIRECTORY/sonarr_api_key
```

### Anti-Pattern: sops-nix ist verboten {#sops-verboten}

sops-nix / agenix sind für q958 explizit verboten. Begründung und Assertion in:

- [ANTIPATTERNS.md#sops-nix](ANTIPATTERNS.md#sops-nix)
- [ADR-024](../adr/024-systemd-creds-tpm.md)
- `modules/00-core/05-creds.nix` — Build-Fehler wenn sops aktiviert

## Hardened Core (Stufe 9 / Production) {#hardened-core}

`modules/27-hardened-core.nix` — nur mit `rollout.stufe >= 9`:

- Deaktiviert: ModemManager, udisks2, cups, bluetooth, wpa_supplicant, upower
- `security.hideProcessInformation = true`
- Maskiert: `plymouth-quit-wait`, `systemd-networkd-wait-online`
- **pcscd bleibt an** (YubiKey/LUKS)
- `lockKernelModules` default `false` — nur bei Bedarf aktivieren

## Kernel-Härtung (Stufe 8+) {#kernel-haertung}

`modules/26-kernel-hardening.nix` — aktiv ab Rollout Stufe 8:

- Sysctl: `kptr_restrict`, `ptrace_scope`, SYN-Cookies, Martian-Logging
- Boot: `init_on_alloc`, `slub_debug`, `mitigations=auto`
- Mounts: `/tmp`, `/dev/shm`, `/run/lock` mit `noexec,nosuid,nodev`
- **VPN:** `ip_forward` bleibt an, solange `vpn-confinement` aktiv ist

## Fail2ban {#fail2ban}

Mit aktiver nftables-Firewall: `banaction = nftables-f2b-set` — Bans landen im Set `f2b_blocked` (siehe [GUIDE-nftables-hardening](GUIDE-nftables-hardening.md#fail2ban)).

## Notfall {#notfall}

- Dropbear Rescue: Stufe 8+, Port 2222
- Notfall-User `nixos`: `machines/q958/profile.nix` → `access.emergency`

## Siehe auch {#siehe-auch}

- [ADR-024 — systemd-creds + TPM2](../adr/024-systemd-creds-tpm.md) — Secrets-Strategie ab Stufe 9
- [ADR-010 — Production SSH + Impermanence](../adr/010-production-ssh-impermanence.md) — SSH-Härtung und tmpfs-Root-Entscheidung
- [GUIDE-nftables-hardening.md](GUIDE-nftables-hardening.md) — L4-Firewall, Fail2ban↔nftables, skuid-Segmentierung
- [ANTIPATTERNS.md#sops-nix](ANTIPATTERNS.md#sops-nix) — warum kein sops-nix
- [RUNBOOK.md](../RUNBOOK.md) — Quick-Fix bei Sicherheits-Incidents
