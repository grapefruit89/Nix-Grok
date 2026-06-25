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
| [001](001-dns-dot-fail-closed.md) | DNS-over-TLS, Blocky-only, fail-closed | accepted | 2026-06-17 | Blocky, resolv.conf, LAN |
| [002](002-ipv6-homelab-v4-only.md) | IPv6 Homelab ad acta (v4-only LAN) | accepted | 2026-06-17 | eno1, nftables, Blocky, CrowdSec |
| [003](003-oom-cgroup-isolation.md) | RAM-Isolation per systemd cgroup | accepted | 2026-06-17 | memory-policy.nix, alle Caps |
| [004](004-unix-socket-upstreams.md) | Unix-Socket-Upstreams für Caddy | accepted | 2026-06-17 | unix-sockets.nix, caddy-helpers |
| [005](005-critical-systemd-restart.md) | Restart=always für kritische Dienste | accepted | 2026-06-17 | critical-systemd.nix, Gatus |
| [006](006-sops-migration-path.md) | SOPS-Migration vs. secrets-provision | accepted | 2026-06-17 | 10-gateway, DDNS, Cloudflare |
| [007](007-dendritic-one-file-per-service.md) | Dendritische Module — eine Datei pro Dienst | accepted | 2026-06-17 | 50-media/*, rollout.nix |
| [008](008-nftables-l4-hardening.md) | nftables L4-Härtung (KB-Synthese) | accepted | 2026-06-17 | 15-firewall, uid-registry, fail2ban |
| [009](009-vpn-leak-check.md) | VPN-NetNS-Leak-Check (Timer) | accepted | 2026-06-17 | 10-vpn-confinement, sabnzbd, prowlarr |
| [010](010-production-ssh-impermanence.md) | Production SSH-Port, PermitTTY, Impermanence | accepted | 2026-06-17 | rollout.nix, 20-security, 30-storage |

## Wann neues ADR?

- Architektur-Entscheidung ist **schwer rückgängig** oder **sicherheitsrelevant**
- Mehrere Module/`profile.nix` betroffen
- KI soll nicht „raten“, sondern die **Begründung** lesen

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