---
meta:
  role: doc
  purpose: Leichtgewichtige Spec-IDs — Pfad, ADR, optional meta.id in Code-Headern
  tags:
    - registry
    - spec
---

# SPEC Registry

> Stabile IDs für KI und Mensch — **kein** Nix-Build-Overhead (`options.my.meta.*` bewusst nicht).
> IDs stehen optional im comment-YAML-Header (`meta.id`) und hier in der Tabelle.

## Kern-Bibliotheken

| ID | Pfad | ADR / Doku |
|----|------|------------|
| NIXH-05-LIB-001 | `lib/dns-map.nix` | — |
| NIXH-05-LIB-002 | `lib/service-factory.nix` | — |
| NIXH-05-LIB-003 | `lib/memory-policy.nix` | [003](adr/003-oom-cgroup-isolation.md) |
| NIXH-05-LIB-004 | `lib/critical-systemd.nix` | [005](adr/005-critical-systemd-restart.md) |
| NIXH-05-LIB-005 | `lib/unix-sockets.nix` | [004](adr/004-unix-socket-upstreams.md) |
| NIXH-05-LIB-006 | `lib/services-spec.nix` | `docs/ROADMAP.md` (mynixos #1) |
| NIXH-05-LIB-007 | `lib/storage-policy.nix` | `AGENTS.md` Tier C |
| NIXH-05-LIB-008 | `lib/forbidden-tech.nix` | — |
| NIXH-05-LIB-009 | `lib/service-enable.nix` | Ingress |
| NIXH-05-LIB-010 | `lib/caddy-ingress.nix` | `docs/ROADMAP.md` #5 |

## Policy-Module

| ID | Pfad | ADR / Doku |
|----|------|------------|
| NIXH-05-MOD-001 | `modules/05-services-spec.nix` | Zonen + Port-SSoT |
| NIXH-05-MOD-002 | `modules/05-storage-policy.nix` | Tier-C-Exclusion |
| NIXH-05-MOD-003 | `modules/05-forbidden-tech.nix` | Docker/Cron/nftables |
| NIXH-05-MOD-004 | `modules/05-runtime-guard.nix` | Runtime-Watchdog |
| NIXH-05-MOD-005 | `modules/05-sops.nix` | [006](adr/006-sops-migration-path.md) |
| NIXH-10-ING-001 | `modules/10-ingress.nix` | Spec-Ingress |
| NIXH-10-VPN-001 | `modules/10-vpn-confinement.nix` | NetNS Usenet |

## Gateway & Policy

| ID | Pfad | ADR / Doku |
|----|------|------------|
| NIXH-10-GTW-001 | `modules/10-gateway.nix` | [006](adr/006-sops-migration-path.md) |
| NIXH-90-POL-001 | `modules/91-security-assertions.nix` | `docs/SECURITY.md` |

## Media & Apps

| ID | Pfad | ADR / Doku |
|----|------|------------|
| NIXH-50-MED-001 | `modules/50-media/audiobookshelf.nix` | `docs/memory_oom.md` |
| NIXH-60-APP-TPL | `modules/60-apps/SERVICE_TEMPLATE.nix` | — |

## DNS-Hostnamen (SSOT)

Alle FQDNs: `lib/dns-map.nix` → `host "<schlüssel>"`. Beispiele:

| Schlüssel | FQDN (domain = nix.m7c5.de) |
|-----------|----------------------------|
| `linkwarden` | `links.nix.m7c5.de` |
| `audiobookshelf` | `audiobookshelf.nix.m7c5.de` |
| `vaultwarden` | `vault.nix.m7c5.de` |
| `ddns-updater` | `ddns.nix.m7c5.de` |

## Neue Einträge

1. Optional `meta.id: NIXH-…` im Datei-Header
2. Zeile in dieser Tabelle
3. Bei Architektur-Entscheidung: ADR in `docs/adr/`