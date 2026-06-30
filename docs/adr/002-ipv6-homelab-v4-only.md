---
meta:
  role: doc
  purpose: ADR-002 IPv6 Homelab v4-only auf eno1
  status: accepted
  date: 2026-06-17
  betrifft:
    - machines/q958/profile.nix
    - machines/q958/network.nix
    - machines/q958/access.nix
    - modules/10-network/11-network.nix
    - modules/15-firewall.nix
    - modules/40-observability/crowdsec.nix
  docs:
    - docs/adr/README.md
    - docs/adr/001-dns-dot-fail-closed.md
    - docs/adr/008-nftables-l4-hardening.md
  tags:
    - adr
    - ipv6
    - nftables
    - network
---

# ADR-002: IPv6 Homelab ad acta (v4-only LAN) {#adr-002}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Fritzbox-LAN ist **IPv4-praktisch** (`192.168.2.0/24`); IPv6 auf `eno1` bringt Komplexität ohne Nutzen.
- Geo-Blocklist (`modules/15-firewall.nix`) und CrowdSec-Integration sind **v4-fokussiert** ([ADR-008](008-nftables-l4-hardening.md)).
- nftables mit parallelen v4/v6-Regeln erhöht Fehlerrisiko (z. B. `ip6` vs `meta nfproto ipv6`).
- DNS: Technitium soll konsistent **nur v4** zum WAN und **keine AAAA** ins LAN liefern ([ADR-001](001-dns-dot-fail-closed.md)).
- **Tailscale** Mesh-VPN darf nicht gebrochen werden.

## Entscheidung {#entscheidung}

1. **`profile.nix`:** `ipv6.disableOnInterfaces = [ "eno1" ]`, `ipv6.firewall = false`.
2. **Kernel/sysctl** auf `eno1`: `disable_ipv6=1`, `accept_ra=0`, `autoconf=0`.
3. **systemd-networkd** (`access.nix`): `IPv6AcceptRA = no` auf LAN.
4. **nftables** ([ADR-008](008-nftables-l4-hardening.md)): kein `crowdsec_blocked_ipv6`; Drop-Regel für `meta nfproto ipv6` auf `iifname eno1`.
5. **CrowdSec bouncer:** `nftables.ipv6.enabled = false`.
6. **Technitium/DNS:** `connectIPVersion = v4`, `filtering.queryTypes = [ "AAAA" ]`, Sandbox ohne `AF_INET6`.
7. **Assertion:** `ipv6.firewall == false` wenn Technitium/DNS aktiv.
8. **Ausnahme:** `tailscale0` — IPv6 **nicht** abschalten.

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Weniger Firewall-/DNS-/Monitoring-Komplexität.
- Einheitliches v4-Modell für Geo-Block, CrowdSec, DNS ([ADR-008](008-nftables-l4-hardening.md)).
- Klare Dokumentation und Build-Assertions gegen v6-Regression.

### Negativ / Trade-offs {#negativ}

- Kein natives IPv6 im LAN — spätere Aktivierung braucht koordinierten Rollout (siehe unten).
- Dual-Stack-Clients im LAN bekommen keine AAAA von Technitium.
- Manche Tools erwarten v6 — müssen über v4 oder Tailscale.

### Wieder aktivieren (Checkliste) {#reaktivierung}

1. `profile.nix`: `ipv6.firewall = true`, `disableOnInterfaces = [ ]`
2. DNS: AAAA-Filter entfernen, `connectIPVersion = dual`
3. nftables/CrowdSec v6-Regeln reaktivieren
4. Rebuild + Verifikation

### Implementierung {#implementierung}

| Schicht | Datei |
|---------|-------|
| Daten | `machines/q958/profile.nix` |
| Verdrahtung | `machines/q958/network.nix` |
| Netzwerk | `modules/10-network/11-network.nix` |
| Firewall | `modules/15-firewall.nix` |
| CrowdSec | `modules/40-observability/crowdsec.nix` |
| LAN | `machines/q958/access.nix` |

### Verifikation {#verifikation}

```bash
sysctl net.ipv6.conf.eno1.disable_ipv6       # → 1
sysctl net.ipv6.conf.tailscale0.disable_ipv6  # → 0
dig @127.0.0.1 google.com AAAA +short         # leer
```

## Alternativen verworfen {#alternativen}

- **Dual-Stack (v4+v6)** — nftables-Komplexität verdoppelt sich, CrowdSec braucht v6-Sets, DNS filtert dann nicht mehr. Kein Nutzen für ein LAN das v6 ignoriert. Abgelehnt.
- **IPv6 nur intern (ULA)** — bringt keinen WAN-Nutzen, verdoppelt trotzdem Firewall-Regeln. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-001 — DNS-over-TLS](001-dns-dot-fail-closed.md) — DNS AAAA-Filter + v4-only Resolver-Konfiguration
- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — Firewall-Regeln die diese v4-only Entscheidung voraussetzen
- [GUIDE-network-database.md](../guides/GUIDE-network-database.md) — DNS + PostgreSQL Betriebsguide (v4-only Kontext)
- [GUIDE-data-management.md#rsync](../guides/GUIDE-data-management.md#rsync) — rsync braucht explizite IPv4-Ziele auf q958
