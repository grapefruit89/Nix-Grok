---
meta:
  role: doc
  purpose: ADR-008 nftables L4-Härtung — KB-Synthese, skuid-Segmentierung, CrowdSec/Fail2ban-Integration
  status: accepted
  date: 2026-06-17
  error_pattern: "nft.*error|Error in line.*nftables|nftables.*failed to load|ruleset.*error"
  quick_fix: "nft -c -f /etc/nftables.conf && systemctl restart nftables"
  services: []
  betrifft:
    - lib/nftables-rules.nix
    - modules/15-firewall.nix
    - modules/20-security/crowdsec.nix
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-nftables-hardening.md
    - docs/adr/001-dns-dot-fail-closed.md
    - docs/adr/002-ipv6-homelab-v4-only.md
    - docs/adr/009-vpn-leak-check.md
    - docs/adr/011-unified-port-uid-schema.md
  tags:
    - adr
    - nftables
    - firewall
    - crowdsec
    - fail2ban
    - skuid
---

# ADR-008: nftables L4-Härtung (KB-Synthese) {#adr-008}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 (Single-NIC, eno1 = LAN) |
| **Rollout** | Stufe 8+ |

## Kontext {#kontext}

- KB `GUIDE-Nftables-Firewall-Mastery` und `security-hardening-baseline` liefern bewährte L4-Patterns.
- Bisher: inline ruleset in `15-firewall.nix`, kein `checkRuleset`, kein Fail2ban-Set, keine skuid-Regeln.
- Geo/Rate bleiben in **nftables** — Technitium/DNS macht DNS-Adblock, nicht L4 ([ADR-001](001-dns-dot-fail-closed.md)).
- skuid-Segmentierung setzt statische UIDs voraus — bereitgestellt durch [ADR-011](011-unified-port-uid-schema.md).
- v6-Regeln entfallen auf eno1 — [ADR-002](002-ipv6-homelab-v4-only.md) deaktiviert IPv6 auf dem LAN-Interface.

## Entscheidung {#entscheidung}

### Hohe Priorität (Stufe 8, implementiert) {#hohe-prioritaet}

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

### Mittlere Priorität (Stufe 8+, skuid-Segmentierung) {#skuid-segmentierung}

Voraussetzung: `lib/uid-registry.nix` ([ADR-011](011-unified-port-uid-schema.md#single-source)) + `modules/05-uid-registry.nix`.

- **Prowlarr/SAB (UID 5006/5007):** Host-`output` — Egress nur LAN, Tailscale, VPN-Bridges
- **Sonarr/Radarr/Readarr (UID 5003–5005):** WAN-Input nur LAN + Tailscale (`100.64.0.0/10`)
- **PostgreSQL/Valkey:** TCP 5432/6379 nur `127.0.0.0/8`

### Bewusst zurückgestellt {#zurueckgestellt}

| # | Maßnahme | Grund |
|---|----------|-------|
| — | `flowtable` ingress hook | Kernel/Setup-abhängig, q958 Single-NIC |
| — | WAN `iifname eno1` Bogon | eno1 ist LAN — `lanInterface` stattdessen |

## Diagnose {#diagnose}

**Symptom:** Ruleset lädt nicht nach Rebuild, oder Dienste nicht mehr erreichbar nach Firewall-Änderung.

```bash
# Aktuelles Ruleset anzeigen
sudo nft list ruleset | head -50

# Syntax-Check ohne Laden
sudo nft -c -f /etc/nftables.conf

# nftables-Service-Status
systemctl status nftables --no-pager
journalctl -u nftables -n 20 --no-pager

# Aktive Sets (CrowdSec, Fail2ban, Portscan)
sudo nft list set inet filter crowdsec_blocked_ipv4
sudo nft list set inet filter f2b_blocked_ipv4
```

## Fix {#fix}

```bash
# 1. Syntax-Fehler im Ruleset identifizieren
sudo nft -c -f /etc/nftables.conf
# Fehler: "Error in line X: ..."

# 2. Fix in lib/nftables-rules.nix oder modules/15-firewall.nix
# 3. checkRuleset=true bricht Rebuild bei Syntaxfehler — Dry-Build nutzen
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# 4. Dienst nach Fix neu laden
sudo systemctl reload nftables || sudo systemctl restart nftables

# 5. Verifikation
sudo nft list ruleset | grep -E "chain|policy"
```

## Architektur {#architektur}

```
lib/nftables-rules.nix   ← Generator (Sets, Chains, skuid)
modules/15-firewall.nix  ← Options, checkRuleset, Geo-IP-Timer
modules/20-security/     ← Fail2ban → f2b_blocked_ipv4, CrowdSec-Bouncer
```

## Konsequenzen {#konsequenzen}

- Syntaxfehler im Ruleset → kein Lockout (`checkRuleset` bricht Build statt zur Laufzeit).
- Fail2ban-Bans landen im gleichen `inet filter` wie CrowdSec/Geo.
- skuid braucht statische UIDs — Registry ([ADR-011](011-unified-port-uid-schema.md)) ist Pflicht.
- Jellyfin-Mediathek: RO via `BindReadOnlyPaths` (`jellyfin.nix`), nicht nftables.
- IPv6 auf eno1 deaktiviert ([ADR-002](002-ipv6-homelab-v4-only.md)) — keine v6-Firewall-Komplexität.

## Alternativen verworfen {#alternativen}

- **iptables** — veraltet, kein atomares Laden. Abgelehnt.
- **Kernel-Firewall via systemd** — weniger flexibel für dynamische Sets (CrowdSec, Geo). Abgelehnt.
- **fail2ban-nur-Blocking ohne nftables-Sets** — Integration mit CrowdSec-Sets nicht möglich. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-06-17 | Initial — KB-Mitnahme Stufe 8 |

## Siehe auch {#siehe-auch}

- [ADR-001 — DNS-over-TLS](001-dns-dot-fail-closed.md) — Geo/Rate in nftables, nicht DNS-Ebene
- [ADR-002 — IPv6 v4-only](002-ipv6-homelab-v4-only.md) — kein v6-Ruleset auf eno1
- [ADR-009 — VPN-Leak-Check](009-vpn-leak-check.md) — NetNS-Egress-Regeln ergänzen nftables
- [ADR-011 — Port/UID-Schema](011-unified-port-uid-schema.md) — statische UIDs für skuid-Regeln
- [GUIDE-nftables-hardening](../guides/GUIDE-nftables-hardening.md) — ausführliche Implementierungsanleitung
