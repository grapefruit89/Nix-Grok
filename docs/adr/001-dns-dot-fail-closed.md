---
meta:
  role: doc
  purpose: ADR-001 DNS-over-TLS, fail-closed (Technitium + API-DoT-Configure)
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - dns
---

# ADR-001: DNS-over-TLS, fail-closed

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Letzte Änderung** | 2026-06-28 (Blocky→Technitium) |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext

- Homelab braucht einen **einzigen** DNS-Resolver für Host und optional LAN.
- WAN-DNS soll **nicht** im Klartext das Internet verlassen.
- Regressionen (jemand trägt `1.1.1.1` in `nameservers`) passierten in der Vergangenheit via `resolvconf` und stale `/etc/resolv.conf`.
- Caddy ACME/DNS-Challenges und alle Host-Lookups hängen an funktionierendem DNS.

## Entscheidung

### Aktuelle Implementierung (ab 2026-06-28): Technitium

1. **Technitium DNS Server** ist der einzige Resolver (`rollout.nix` Stufe 2+).
2. **WAN-Upstreams** ausschließlich DoT — konfiguriert via `systemd.services.technitium-dns-configure`
   (Oneshot-Service, API-Call mit `admin`/`admin`, idempotent per Marker-Datei).
3. **Forwarder-Liste** wird aus `my.configs.network.dnsBootstrap` abgeleitet (SSoT in
   `machines/q958/profile.nix`): `tcp-tls:IP:853` → `IP:853` für Technitium-API.
4. **Host-DNS fail-closed:**
   - `networking.nameservers = [ “127.0.0.1” ]`
   - `/etc/resolv.conf` NixOS-verwaltet, nur `127.0.0.1`
   - `networking.resolvconf.enable = false`
5. **Build-Assertions:** `modules/10-network/11-network.nix` — `nameservers != [ “127.0.0.1” ]` bricht den Build.
6. **Kein Fallback** auf Klartext-DNS wenn Technitium down — `Restart=always`, Alarm via Gatus.

### Limitation vs. Original (Blocky)

Blocky konfigurierte DoT-Upstreams als **NixOS-Option** (Build-Zeit). Technitium's NixOS-Modul
hat keine Forwarder-Option — die Konfiguration erfolgt via REST-API beim ersten Start
(Runtime). Wenn der Betreiber die `admin`/`admin`-Credentials ändert, bevor `technitium-dns-configure`
läuft, muss DoT **manuell** im Web-UI (`http://localhost:1002`) unter Settings → Forwarder
gesetzt werden:

```
Forwarder Protocol: DNS-over-TLS
Forwarder: 1.1.1.1:853, 1.0.0.1:853, 9.9.9.9:853, 149.112.112.112:853, 194.242.2.2:853
```

## Konsequenzen

### Positiv

- Technitium hat Web-UI, DNS-Blocklisten, Query-Log — deutlich mehr Funktionen als Blocky.
- DoT-Konfiguration ist automatisiert (einmalig beim ersten Start).
- Klare Kette: `Host/LAN → Technitium → DoT → Internet`.

### Negativ / Trade-offs

- DoT-Konfiguration ist **Runtime** (nicht Build-Zeit wie bei Blocky) — manuelle Fallback-Option dokumentiert (s.o.).
- Technitium-Ausfall = **kein DNS** auf dem Host (bewusst fail-closed).
- LAN-Clients nutzen Technitium nur, wenn Fritzbox/DHCP DNS auf `192.168.2.73` zeigt.

### Implementierung

| Schicht | Datei |
|---------|-------|
| Daten / DoT-Server | `machines/q958/profile.nix` (`network.dns.bootstrap`) |
| Verdrahtung | `machines/q958/network.nix` |
| Modul | `modules/10-network/11-network.nix` |
| DoT-Configure-Service | `systemd.services.technitium-dns-configure` (in 11-network.nix) |

### Verifikation

```bash
cat /etc/resolv.conf                          # nur nameserver 127.0.0.1
systemctl status technitium-dns-configure     # Marker gesetzt?
dig @127.0.0.1 cloudflare.com +short
# Im Technitium Web-UI: Settings → Forwarder Protocol = Tls
```

## Verwandte ADRs

- [002 — IPv6 v4-only](002-ipv6-homelab-v4-only.md)