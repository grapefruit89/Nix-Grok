---
meta:
  role: doc
  purpose: ADR-Index — alle Architecture Decision Records
  tags:
    - adr
    - index
---

# Architecture Decision Records (ADR)

> **Format:** Kontext → Entscheidung → Konsequenzen · **Status:** `accepted` = live auf q958  
> **Maschinenlesbar:** YAML-Frontmatter · **KI:** zuerst hier, dann verlinkte ADR-Datei

## Index

| ID | Titel | Status | Datum | Betrifft |
|----|-------|--------|-------|----------|
| [001](001-dns-dot-fail-closed.md) | DNS-over-TLS, fail-closed (Blocky→Technitium) | accepted | 2026-06-17 | Technitium, resolv.conf, LAN |
| [002](002-ipv6-homelab-v4-only.md) | IPv6 Homelab ad acta (v4-only LAN) | accepted | 2026-06-17 | eno1, nftables, Blocky, CrowdSec |
| [003](003-oom-cgroup-isolation.md) | RAM-Isolation per systemd cgroup | accepted | 2026-06-17 | memory-policy.nix, alle Caps |
| [004](004-unix-socket-upstreams.md) | Unix-Socket-Upstreams für Caddy | accepted | 2026-06-17 | unix-sockets.nix, caddy-helpers |
| [005](005-critical-systemd-restart.md) | Restart=always für kritische Dienste | accepted | 2026-06-17 | critical-systemd.nix, Gatus |
| [006](006-sops-migration-path.md) | SOPS-Migration vs. secrets-provision | accepted | 2026-06-17 | 10-gateway, DDNS, Cloudflare |
| [007](007-dendritic-one-file-per-service.md) | Dendritische Module — eine Datei pro Dienst | accepted | 2026-06-17 | 50-media/*, rollout.nix |
| [008](008-nftables-l4-hardening.md) | nftables L4-Härtung (KB-Synthese) | accepted | 2026-06-17 | 15-firewall, uid-registry, fail2ban |
| [009](009-vpn-leak-check.md) | VPN-NetNS-Leak-Check (Timer) | accepted | 2026-06-17 | 10-vpn-confinement, sabnzbd, prowlarr |
| [010](010-production-ssh-impermanence.md) | Production SSH-Port, PermitTTY, Impermanence | accepted | 2026-06-17 | rollout.nix, 20-security, 30-storage |
| [011](011-unified-port-uid-schema.md) | Unified Port=UID=FolderPrefix Schema (4-stellig) | accepted | 2026-06-27 | uid-registry, unix-sockets, server-map |
| [012](012-modern-cli-tools.md) | Moderne CLI-Tools systemweit (bat, eza, fd, rg, nh) | accepted | 2026-06-28 | 00-core, shell-aliases, CLAUDE.md |
| [013](013-flake-portability.md) | Flake-Portabilität — Reproduzierbarkeit ohne Experimente | accepted | 2026-06-29 | flake.lock, 00-core, experimental-features |
| [014](014-caddy-security-headers-trusted-proxies.md) | Caddy Security-Härtung — Headers + trusted_proxies | accepted | 2026-06-29 | caddy-snippets.nix, 11-network.nix |
| [015](015-cpu-power-profiles-daemon-thermald.md) | CPU-Energieverwaltung — power-profiles-daemon + thermald (Intel HWP/EPP) | accepted | 2026-06-29 | machines/q958/default.nix |
| [016](016-caddy-security-headers-coop-scanners.md) | Caddy Security-Härtung II — Server-Header, COOP, Scanner-Blocking | accepted | 2026-06-29 | lib/caddy-snippets.nix |
| [017](017-caddy-health-checks-error-fallback.md) | Caddy Health Checks — 503-Fallback für ausgefallene Dienste | accepted | 2026-06-29 | lib/caddy-snippets.nix, lib/caddy-ingress.nix |
| [018](018-caddy-dual-log-dsgvo.md) | Caddy Dual-Log — DSGVO + journald für CrowdSec | accepted | 2026-06-29 | lib/caddy-snippets.nix |
| [019](019-uds-first-philosophy.md) | Unix-Domain-Sockets als primäres IPC-Protokoll | accepted | 2026-06-30 | caddy-ingress, alle Backend-Dienste |
| [020](020-no-legacy-explicit-stack.md) | Explizit ersetzte Technologien — Legacy-Stack | accepted | 2026-06-30 | rollout.nix, flake.nix |
| [021](021-sops-impermanence-boot-timing.md) | SOPS Boot-Timing mit Impermanence | withdrawn | 2026-07-05 | → ADR-024 (sops-nix entfällt) |
| [022](022-no-raid-distance-parity.md) | Keine lokale Redundanz — Geografische Distanz statt RAID | accepted | 2026-06-30 | storage, restic |
| [023](023-backup-philosophy.md) | Backup-Philosophie — Nur Unwiederbringliches sichern | accepted | 2026-06-30 | restic-backup.nix |
| [024](024-systemd-creds-tpm.md) | systemd-creds + TPM2 statt sops-nix | accepted | 2026-07-05 | modules/00-core/05-creds.nix, flake.nix |
| [025](025-pocket-id-oidc-provider.md) | Pocket-ID als OIDC/Passkey Provider | accepted | 2026-07-05 | modules/10-network/17-pocket-id.nix |
| [026](026-kernel-hardening-sysctl.md) | Kernel-Härtung — sysctl, Boot-Parameter, Mount-Flags | accepted | 2026-07-05 | modules/20-security/26-kernel-hardening.nix |
| [027](027-kernel-slim-module-policy.md) | Kernel-Slim — Modul-Blacklisting-Policy (Whitelist/Blacklist) | accepted | 2026-07-05 | lib/kernel/, modules/20-security/25-kernel-policy.nix |
| [028](028-systemd-service-isolation.md) | Systemd Service Isolation — mkHardened Factory | accepted | 2026-07-05 | lib/systemd-hardening.nix |
| [029](029-mtls-zero-trust-internal.md) | mTLS Zero-Trust — Interne Dienst-Kommunikation | proposed | 2026-07-05 | (noch nicht implementiert) |
| [030](030-media-stack-factory-hardening.md) | Media-Stack Inventory — was bereits implementiert war | accepted | 2026-07-05 | 51-jellyfin.nix, arr-helper.nix, caddy-ingress.nix |
| [031](031-caddy-zones-konzept.md) | Caddy-Zonen-Konzept — admin-hangar / family-pocketid / public | accepted | 2026-07-05 | lib/services-spec.nix, lib/caddy-ingress.nix |

## Wann neues ADR?

- Architektur-Entscheidung ist **schwer rückgängig** oder **sicherheitsrelevant**
- Mehrere Module/`profile.nix` betroffen
- KI soll nicht „raten", sondern die **Begründung** lesen

## Dateiname

`NNN-kurz-thema.md` — fortlaufende Nummer, kebab-case.

## Verknüpfung im Code

In `.nix`-Header unter `meta.docs`:

```nix
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
```

Nicht: tote `ADR-10-network.md`-Pfade ohne Datei.

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-06-17 | ADR 001–003 initial |
| 2026-06-17 | ADR 004–006 (Fabrik, DDNS, SOPS-Pfad) |
| 2026-06-17 | ADR-Index angelegt |
| 2026-06-17 | ADR 007–008 (Dendritic, nftables KB) |
| 2026-06-17 | ADR 009–010 (nix-hermes Audit: VPN leak, Production-Modus) |
| 2026-06-27 | ADR 011 (Unified Port=UID=FolderPrefix, Server-Map) |
| 2026-06-28 | ADR 001 aktualisiert (Blocky→Technitium+API-DoT-Configure); ADR 012 (Moderne CLI-Tools) |
| 2026-06-29 | ADR 013–017: Flake-Portabilität, Caddy Security-Härtung I+II, CPU power-profiles-daemon+thermald, Caddy Health Checks |
| 2026-07-05 | ADR 018–020 (Caddy Dual-Log, UDS-First, Legacy-Stack) nachgetragen; ADR 021 withdrawn; ADR 022–023 (RAID, Backup); ADR 024 (systemd-creds); ADR 025 (Pocket-ID OIDC) |
| 2026-07-05 | ADR 026–028 (Kernel-Härtung, Kernel-Slim, Systemd-Isolation); ADR 029 (mTLS proposed); ADR 030 (Media-Stack Inventory) |
| 2026-07-05 | ADR 031 (Caddy-Zonen-Konzept: admin-hangar / family-pocketid / public) |
