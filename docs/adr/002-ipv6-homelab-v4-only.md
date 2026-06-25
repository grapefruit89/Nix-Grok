---
meta:
  role: doc
  purpose: ADR-002 IPv6 Homelab v4-only auf eno1
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - ipv6
---

# ADR-002: IPv6 Homelab ad acta (v4-only LAN)

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Fritzbox-LAN ist **IPv4-praktisch** (`192.168.2.0/24`); IPv6 auf `eno1` bringt Komplexität ohne Nutzen.
- Geo-Blocklist (`modules/15-firewall.nix`) und CrowdSec-Integration sind **v4-fokussiert**.
- nftables mit parallelen v4/v6-Regeln erhöht Fehlerrisiko (z. B. `ip6` vs `meta nfproto ipv6`).
- Blocky soll konsistent **nur v4** zum WAN und **keine AAAA** ins LAN liefern.
- **Tailscale** Mesh-VPN darf nicht gebrochen werden.

## Entscheidung

1. **`profile.nix`:** `ipv6.disableOnInterfaces = [ "eno1" ]`, `ipv6.firewall = false`.
2. **Kernel/sysctl** auf `eno1`: `disable_ipv6=1`, `accept_ra=0`, `autoconf=0`.
3. **systemd-networkd** (`access.nix`): `IPv6AcceptRA = no` auf LAN.
4. **nftables:** kein `crowdsec_blocked_ipv6`; Drop-Regel für `meta nfproto ipv6` auf `iifname eno1`.
5. **CrowdSec bouncer:** `nftables.ipv6.enabled = false`.
6. **Blocky:** `connectIPVersion = v4`, `filtering.queryTypes = [ "AAAA" ]`, Sandbox ohne `AF_INET6`.
7. **Assertion:** `ipv6.firewall == false` wenn Blocky aktiv.
8. **Ausnahme:** `tailscale0` — IPv6 **nicht** abschalten.

## Konsequenzen

### Positiv

- Weniger Firewall-/DNS-/Monitoring-Komplexität.
- Einheitliches v4-Modell für Geo-Block, CrowdSec, Blocky.
- Klare Dokumentation und Build-Assertions gegen v6-Regression.

### Negativ / Trade-offs

- Kein natives IPv6 im LAN — spätere Aktivierung braucht koordinierten Rollout (siehe unten).
- Dual-Stack-Clients im LAN bekommen keine AAAA von Blocky.
- Manche Tools erwarten v6 — müssen über v4 oder Tailscale.

### Wieder aktivieren (Checkliste)

1. `profile.nix`: `ipv6.firewall = true`, `disableOnInterfaces = [ ]`
2. Blocky: AAAA-Filter entfernen, `connectIPVersion = dual`
3. nftables/CrowdSec v6-Regeln reaktivieren
4. Rebuild + Verifikation

### Implementierung

| Schicht | Datei |
|---------|-------|
| Daten | `machines/q958/profile.nix` |
| Verdrahtung | `machines/q958/network.nix` |
| Netzwerk | `modules/10-network.nix` |
| Firewall | `modules/15-firewall.nix` |
| CrowdSec | `modules/40-observability.nix` |
| LAN | `machines/q958/access.nix` |

### Verifikation

```bash
sysctl net.ipv6.conf.eno1.disable_ipv6    # → 1
sysctl net.ipv6.conf.tailscale0.disable_ipv6 # → 0
dig @127.0.0.1 google.com AAAA +short       # leer
```

## Verwandte ADRs

- [001 — DNS DoT](001-dns-dot-fail-closed.md)