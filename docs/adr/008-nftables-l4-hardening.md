---
meta:
  role: doc
  purpose: ADR-008 nftables L4-Härtung (KB-Synthese)
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-nftables-hardening.md
  lib:
    - lib/nftables-rules.nix
  tags:
    - adr
    - nftables
---

# ADR-008: nftables L4-Härtung (KB-Synthese)

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 (Single-NIC, eno1 = LAN) |
| **Rollout** | Stufe 8+ |

## Kontext

- KB `GUIDE-Nftables-Firewall-Mastery` und `security-hardening-baseline` liefern bewährte L4-Patterns.
- Bisher: inline ruleset in `15-firewall.nix`, kein `checkRuleset`, kein Fail2ban-Set, keine skuid-Regeln.
- Geo/Rate bleiben in **nftables** — Blocky macht DNS-Adblock, nicht L4 (ADR-001 / ROADMAP).

## Entscheidung

### Hohe Priorität (Stufe 8, implementiert)

| # | Maßnahme | Umsetzung |
|---|----------|-----------|
| 1 | `checkRuleset = true` | `networking.nftables.checkRuleset` |
| 2 | Bogon-Drop | `in_wan`: WAN-Interface oder Loopback/Link-Local |
| 3 | TCP-Flag-Scans | NULL, FIN, XMAS in `in_trusted` |
| 4 | SSH parallel | `ct count over 3` + 10/minute |
| 5 | UDP-Flood | rate-limit, Ausnahme Tailscale-UDP |
| 6 | CrowdSec/Geo früh | nach invalid/frag, vor HTTP/SSH |
| 7 | Fail2ban-Set | `f2b_blocked_ipv4` + Action `nftables-f2b-set` |
| 8 | Portscan | dynamic set `portscan`, 24h timeout |
| 9 | HTTP ct limit | 30/s burst + web_meter pro IP |
| 10 | Split chains | `in_trusted` → `in_lan` → `in_wan` |
| 11 | NOTRACK Tailscale | optional `table inet raw` |

### Mittlere Priorität (Stufe 8+, `skuidSegmentation.enable`)

- **Prowlarr/SAB (UID 969/984):** Host-`output` — Egress nur LAN, Tailscale, VPN-Bridges, `192.168.15.0/24`
- **Sonarr/Radarr/Readarr:** WAN-Input nur LAN + Tailscale (`100.64.0.0/10`)
- **PostgreSQL/Valkey:** TCP 5432/6379 nur `127.0.0.0/8`

Voraussetzung: `lib/uid-registry.nix` + `modules/05-uid-registry.nix`.

### Bewusst zurückgestellt

| # | Maßnahme | Grund |
|---|----------|-------|
| 11 | `flowtable` ingress hook | Kernel/Setup-abhängig, q958 Single-NIC |
| — | WAN `iifname eno1` Bogon | eno1 ist LAN — `lanInterface` stattdessen |

## Architektur

```
lib/nftables-rules.nix   ← Generator (Sets, Chains, skuid)
modules/15-firewall.nix  ← Options, checkRuleset, Geo-IP-Timer
modules/20-security.nix  ← Fail2ban → f2b_blocked_ipv4
```

## Konsequenzen

- Syntaxfehler im Ruleset → kein Lockout (`checkRuleset`).
- Fail2ban-Bans landen im gleichen `inet filter` wie CrowdSec/Geo.
- skuid braucht statische UIDs — Registry ist Pflicht.
- Jellyfin-Mediathek: RO via `BindReadOnlyPaths` (`jellyfin.nix`), nicht nftables.

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-06-17 | Initial — KB-Mitnahme Stufe 8 |