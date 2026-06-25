---
meta:
  role: doc
  purpose: ADR-001 DNS-over-TLS, Blocky-only, fail-closed
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - dns
---

# ADR-001: DNS-over-TLS, Blocky-only, fail-closed

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Homelab braucht einen **einzigen** DNS-Resolver für Host und optional LAN.
- AdGuard Home ist **aus** (Port-53-Konflikt mit Blocky).
- WAN-DNS soll **nicht** im Klartext das Internet verlassen.
- Regressionen (jemand trägt `1.1.1.1` in `nameservers`) passierten in der Vergangenheit via `resolvconf` und stale `/etc/resolv.conf`.
- Caddy ACME/DNS-Challenges und alle Host-Lookups hängen an funktionierendem DNS.

## Entscheidung

1. **Blocky** ist der einzige Resolver (`rollout.nix` Stufe 2+).
2. **WAN-Upstreams** ausschließlich verschlüsselt: `tcp-tls:…:853` (DoT), mehrere Provider in `machines/q958/profile.nix`.
3. **Bootstrap** ebenfalls DoT — keine Klartext-Auflösung der Resolver-Hostnames.
4. **Host-DNS fail-closed:**
   - `networking.nameservers = [ "127.0.0.1" ]`
   - `/etc/resolv.conf` NixOS-verwaltet, nur `127.0.0.1`
   - `networking.resolvconf.enable = false`
   - `lan.dns = [ "127.0.0.1" ]` (systemd-networkd **Host**, nicht Fritzbox-DHCP)
5. **Build-Assertions:** `lib/dns-policy.nix` + `modules/10-network.nix` + `machines/q958/access.nix` — Klartext bricht den Build.
6. **Kein Fallback** auf `1.1.1.1` / `8.8.8.8` wenn Blocky down — Alarm via Gatus `critical`, Neustart via `Restart=always`.

## Konsequenzen

### Positiv

- Verschlüsselter DNS-Egress, DNSSEC-Validierung, zentrale Rewrites (`*.nix.m7c5.de`).
- Policy-Regressionen werden beim `nixos-rebuild build` erkannt.
- Klare Kette: `Host/LAN → Blocky → DoT → Internet`.

### Negativ / Trade-offs

- Blocky-Ausfall = **kein DNS** auf dem Host (bewusst, nicht „heimlich umgehen“).
- LAN-Clients nutzen Blocky nur, wenn Fritzbox/DHCP DNS auf `192.168.2.73` zeigt.
- DoT-Port 853 muss am WAN erreichbar sein (kein Captive-Portal-only-DNS).

### Implementierung

| Schicht | Datei |
|---------|-------|
| Daten | `machines/q958/profile.nix` |
| Verdrahtung | `machines/q958/network.nix` |
| Modul | `modules/10-network.nix` |
| Policy | `lib/dns-policy.nix` |

### Verifikation

```bash
cat /etc/resolv.conf                    # nur nameserver 127.0.0.1
dig @127.0.0.1 cloudflare.com +dnssec +short
nixos-rebuild build --flake .#q958      # DNS-Assertions grün
```

## Verwandte ADRs

- [002 — IPv6 v4-only](002-ipv6-homelab-v4-only.md) (Blocky `connectIPVersion=v4`, AAAA-Filter)