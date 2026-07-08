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
> **Nummerierung:** 3-stellig = querschneidend · 4-stellig `DXXX` = D ist Domänenpräfix (1=10-network, 2=20-security, ...)

## Index

### 00-core — Querschneidende Architektur-Prinzipien

| ADR | Titel | Status | Datum |
|-----|-------|--------|-------|
| [003](003-oom-cgroup-isolation.md) | RAM-Isolation per systemd cgroup | accepted | 2026-06-17 |
| [005](005-critical-systemd-restart.md) | Restart=always für kritische Dienste | accepted | 2026-06-17 |
| [007](007-dendritic-one-file-per-service.md) | Dendritische Module — eine Datei pro Dienst | accepted | 2026-06-17 |
| [010](010-production-ssh-impermanence.md) | Production SSH-Port, PermitTTY, Impermanence | accepted | 2026-06-17 |
| [011](011-unified-port-uid-schema.md) | Unified Port=UID=FolderPrefix Schema (4-stellig) | accepted | 2026-06-27 |
| [012](012-modern-cli-tools.md) | Moderne CLI-Tools systemweit (bat, eza, fd, rg, nh) | accepted | 2026-06-28 |
| [013](013-flake-portability.md) | Flake-Portabilität — Reproduzierbarkeit ohne Experimente | accepted | 2026-06-29 |
| [015](015-cpu-power-profiles-daemon-thermald.md) | CPU-Energieverwaltung — power-profiles-daemon + thermald | accepted | 2026-06-29 |
| [020](020-no-legacy-explicit-stack.md) | Explizit ersetzte Technologien — Legacy-Stack | accepted | 2026-06-30 |
| [028](028-systemd-service-isolation.md) | Systemd Service Isolation — mkHardened Factory | accepted | 2026-07-05 |
| [032](032-os-native-first.md) | OS-native-first für kritische Infrastruktur | accepted | 2026-07-06 |

### 10-network — Netzwerk, DNS, Ingress

| ADR | Titel | Status | Datum |
|-----|-------|--------|-------|
| [1001](1001-dns-dot-fail-closed.md) | DNS-over-TLS, fail-closed (Blocky, resolved→DoT direkt) | accepted | 2026-06-17 |
| [1002](1002-ipv6-homelab-v4-only.md) | IPv6 Homelab ad acta (v4-only LAN) | accepted | 2026-06-17 |
| [1004](1004-unix-socket-upstreams.md) | Unix-Socket-Upstreams für Caddy | accepted | 2026-06-17 |
| [1014](1014-caddy-security-headers-trusted-proxies.md) | Caddy Security-Härtung — Headers + trusted_proxies | accepted | 2026-06-29 |
| [1016](1016-caddy-security-headers-coop-scanners.md) | Caddy Security-Härtung II — Server-Header, COOP, Scanner-Blocking | accepted | 2026-06-29 |
| [1017](1017-caddy-health-checks-error-fallback.md) | Caddy Health Checks — 503-Fallback | accepted | 2026-06-29 |
| [1018](1018-caddy-dual-log-dsgvo.md) | Caddy Dual-Log — DSGVO + journald für CrowdSec | accepted | 2026-06-29 |
| [1019](1019-uds-first-philosophy.md) | Unix-Domain-Sockets als primäres IPC-Protokoll | accepted | 2026-06-30 |
| [1025](1025-pocket-id-oidc-provider.md) | Pocket-ID als OIDC/Passkey Provider | accepted | 2026-07-05 |
| [1031](1031-caddy-zones-konzept.md) | Caddy-Zonen-Konzept — internal / family-pocketid / public | accepted | 2026-07-05 |
| [1032](1032-internal-zone-sso.md) | internal Zone — Umbenennung admin-hangar + SSO-Overlay | accepted | 2026-07-08 |

### 20-security — Härtung, Secrets, Firewall

| ADR | Titel | Status | Datum |
|-----|-------|--------|-------|
| [2006](2006-sops-migration-path.md) | SOPS-Migration — SUPERSEDED | superseded | 2026-06-17 |
| [2008](2008-nftables-l4-hardening.md) | nftables L4-Härtung (KB-Synthese) | accepted | 2026-06-17 |
| [2009](2009-vpn-leak-check.md) | VPN-NetNS-Leak-Check (Timer) | accepted | 2026-06-17 |
| [2021](2021-sops-impermanence-boot-timing.md) | SOPS Boot-Timing mit Impermanence — WITHDRAWN | withdrawn | 2026-07-05 |
| [2024](2024-systemd-creds-tpm.md) | systemd-creds + TPM2 statt sops-nix | accepted | 2026-07-05 |
| [2026](2026-kernel-hardening-sysctl.md) | Kernel-Härtung — sysctl, Boot-Parameter, Mount-Flags | accepted | 2026-07-05 |
| [2027](2027-kernel-slim-module-policy.md) | Kernel-Slim — Modul-Blacklisting-Policy | accepted | 2026-07-05 |
| [2029](2029-mtls-zero-trust-internal.md) | mTLS Zero-Trust — Interne Dienst-Kommunikation | proposed | 2026-07-05 |

### 30-storage — Backup, RAID, Persistenz

| ADR | Titel | Status | Datum |
|-----|-------|--------|-------|
| [3022](3022-no-raid-distance-parity.md) | Keine lokale Redundanz — Geografische Distanz statt RAID | accepted | 2026-06-30 |
| [3023](3023-backup-philosophy.md) | Backup-Philosophie — Nur Unwiederbringliches sichern | accepted | 2026-06-30 |

### 50-media — Media-Stack

| ADR | Titel | Status | Datum |
|-----|-------|--------|-------|
| [5030](5030-media-stack-factory-hardening.md) | Media-Stack Inventory — was bereits implementiert war | accepted | 2026-07-05 |


## Wann neues ADR?

- Architektur-Entscheidung ist **schwer rückgängig** oder **sicherheitsrelevant**
- Mehrere Module/`profile.nix` betroffen
- KI soll nicht „raten", sondern die **Begründung** lesen

## Dateiname

`NNN-kurz-thema.md` — 3-stellig, querschneidend (00-core)
`DNNN-kurz-thema.md` — 4-stellig, D = Domänenpräfix (1=10-network, 2=20-security, 3=30-storage, 5=50-media)

## Verknüpfung im Code

In `.nix`-Header unter `meta.docs`:

```nix
#   docs:
#     - docs/adr/1001-dns-dot-fail-closed.md
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
| 2026-06-28 | ADR 001 aktualisiert (resolved→DoT direkt, split0 entfernt); ADR 012 (Moderne CLI-Tools) |
| 2026-06-29 | ADR 013–017: Flake-Portabilität, Caddy Security-Härtung I+II, CPU power-profiles-daemon+thermald, Caddy Health Checks |
| 2026-07-05 | ADR 018–020 (Caddy Dual-Log, UDS-First, Legacy-Stack) nachgetragen; ADR 021 withdrawn; ADR 022–023 (RAID, Backup); ADR 024 (systemd-creds); ADR 025 (Pocket-ID OIDC) |
| 2026-07-05 | ADR 026–028 (Kernel-Härtung, Kernel-Slim, Systemd-Isolation); ADR 029 (mTLS proposed); ADR 030 (Media-Stack Inventory) |
| 2026-07-05 | ADR 1031 (Caddy-Zonen-Konzept: admin-hangar / family-pocketid / public) |
| 2026-07-06 | ADR 032 (OS-native-first Prinzip: lego/security.acme, systemd-creds, DoT als Referenzarchitektur) |
| 2026-07-06 | ADR-Nummerierung auf 4-stellig umgestellt: domänen-spezifische ADRs erhalten Präfix (1xxx/2xxx/3xxx/5xxx); querschneidende ADRs bleiben 3-stellig |
| 2026-07-08 | ADR 1031 aktualisiert (admin-hangar → internal); ADR 1032 (internal Zone + SSO-Overlay) |
