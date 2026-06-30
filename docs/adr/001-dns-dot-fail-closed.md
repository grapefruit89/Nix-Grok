---
meta:
  role: doc
  purpose: ADR-001 DNS-over-TLS, fail-closed (Technitium + API-DoT-Configure)
  status: accepted
  date: 2026-06-17
  error_pattern: "SERVFAIL|failed to resolve|no such host|technitium.*not reachable|connection refused.*1002"
  quick_fix: "systemctl restart technitium; dig @127.0.0.1 cloudflare.com +short"
  services: [technitium, technitium-dns-configure]
  betrifft:
    - machines/q958/profile.nix
    - machines/q958/network.nix
    - modules/10-network/11-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/002-ipv6-homelab-v4-only.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/008-nftables-l4-hardening.md
  tags:
    - adr
    - dns
    - dot
    - technitium
---

# ADR-001: DNS-over-TLS, fail-closed {#adr-001}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Letzte Änderung** | 2026-06-28 (Blocky→Technitium) |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Homelab braucht einen **einzigen** DNS-Resolver für Host und optional LAN.
- WAN-DNS soll **nicht** im Klartext das Internet verlassen.
- Regressionen (jemand trägt `1.1.1.1` in `nameservers`) passierten in der Vergangenheit via `resolvconf` und stale `/etc/resolv.conf`.
- Caddy ACME/DNS-Challenges und alle Host-Lookups hängen an funktionierendem DNS.
- Technitium braucht MemoryMax 500M als Tier-0-Dienst ([ADR-003](003-oom-cgroup-isolation.md#tier-modell)).

## Entscheidung {#entscheidung}

### Aktuelle Implementierung (ab 2026-06-28): Technitium {#technitium}

1. **Technitium DNS Server** ist der einzige Resolver (`rollout.nix` Stufe 2+).
2. **WAN-Upstreams** ausschließlich DoT — konfiguriert via `systemd.services.technitium-dns-configure`
   (Oneshot-Service, API-Call mit `admin`/`admin`, idempotent per Marker-Datei).
3. **Forwarder-Liste** wird aus `my.configs.network.dnsBootstrap` abgeleitet (SSoT in
   `machines/q958/profile.nix`): `tcp-tls:IP:853` → `IP:853` für Technitium-API.
4. **Host-DNS fail-closed:**
   - `networking.nameservers = [ "127.0.0.1" ]`
   - `/etc/resolv.conf` NixOS-verwaltet, nur `127.0.0.1`
   - `networking.resolvconf.enable = false`
5. **Build-Assertions:** `modules/10-network/11-network.nix` — `nameservers != [ "127.0.0.1" ]` bricht den Build.
6. **Kein Fallback** auf Klartext-DNS wenn Technitium down — `Restart=always` ([ADR-005](005-critical-systemd-restart.md)), Alarm via Gatus.

### Limitation vs. Original (Blocky) {#limitation-blocky}

Blocky konfigurierte DoT-Upstreams als **NixOS-Option** (Build-Zeit). Technitium's NixOS-Modul
hat keine Forwarder-Option — die Konfiguration erfolgt via REST-API beim ersten Start
(Runtime). Wenn der Betreiber die `admin`/`admin`-Credentials ändert, bevor `technitium-dns-configure`
läuft, muss DoT **manuell** im Web-UI (`http://localhost:1002`) unter Settings → Forwarder
gesetzt werden:

```
Forwarder Protocol: DNS-over-TLS
Forwarder: 1.1.1.1:853, 1.0.0.1:853, 9.9.9.9:853, 149.112.112.112:853, 194.242.2.2:853
```

## Diagnose {#diagnose}

**Symptom:** DNS-Lookups schlagen fehl; Dienste mit Netzwerkzugriff hängen oder starten nicht.

```bash
# DNS-Funktion prüfen
dig @127.0.0.1 cloudflare.com +short
cat /etc/resolv.conf    # Muss: nameserver 127.0.0.1

# Technitium-Status
systemctl status technitium --no-pager
journalctl -u technitium -n 30 --no-pager | grep -iE "error|fail|warn"

# DoT-Configure-Oneshot prüfen
systemctl status technitium-dns-configure --no-pager
# Marker-Datei prüfen (gesetzt = Konfiguration abgeschlossen)
ls -la /var/lib/technitium/configured.marker 2>/dev/null || echo "NICHT konfiguriert"
```

**Erwarteter Output bei DoT-Fehler:**
```
technitium[...]: Failed to connect to DoT upstream: 1.1.1.1:853
```

## Fix {#fix}

```bash
# 1. Technitium neu starten
sudo systemctl restart technitium
sleep 5
dig @127.0.0.1 cloudflare.com +short

# 2. Falls DoT nicht konfiguriert: Configure-Service neu ausführen
sudo rm -f /var/lib/technitium/configured.marker
sudo systemctl start technitium-dns-configure
systemctl status technitium-dns-configure

# 3. Manuelle DoT-Konfiguration im Web-UI (Fallback):
#    http://localhost:1002 → Settings → Forwarder Protocol: DNS-over-TLS
#    Forwarder: 1.1.1.1:853, 1.0.0.1:853, 9.9.9.9:853

# 4. Build-Assertion prüfen (nameservers muss 127.0.0.1 sein)
grep -r "nameservers" /etc/nixos/machines/q958/
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Technitium hat Web-UI, DNS-Blocklisten, Query-Log — deutlich mehr Funktionen als Blocky.
- DoT-Konfiguration ist automatisiert (einmalig beim ersten Start).
- Klare Kette: `Host/LAN → Technitium → DoT → Internet`.

### Negativ / Trade-offs {#negativ}

- DoT-Konfiguration ist **Runtime** (nicht Build-Zeit wie bei Blocky) — manuelle Fallback-Option dokumentiert (s.o.).
- Technitium-Ausfall = **kein DNS** auf dem Host (bewusst fail-closed).
- LAN-Clients nutzen Technitium nur, wenn Fritzbox/DHCP DNS auf `192.168.2.73` zeigt.

### Implementierung {#implementierung}

| Schicht | Datei |
|---------|-------|
| Daten / DoT-Server | `machines/q958/profile.nix` (`network.dns.bootstrap`) |
| Verdrahtung | `machines/q958/network.nix` |
| Modul | `modules/10-network/11-network.nix` |
| DoT-Configure-Service | `systemd.services.technitium-dns-configure` (in 11-network.nix) |

### Verifikation {#verifikation}

```bash
cat /etc/resolv.conf                          # nur nameserver 127.0.0.1
systemctl status technitium-dns-configure     # Marker gesetzt?
dig @127.0.0.1 cloudflare.com +short
# Im Technitium Web-UI: Settings → Forwarder Protocol = Tls
```

## Alternativen verworfen {#alternativen}

- **Blocky** — konfiguriert DoT als NixOS-Option (Build-Zeit), kein Web-UI. Ersetzt durch Technitium wegen besserer Funktionalität und Web-UI. Verbleibende Blocky-Konfigurationsreferenzen in ADR-002/ADR-003 historisch.
- **Klartext-DNS** — kein DoT, Traffic für Provider sichtbar. Abgelehnt.
- **Fallback auf `1.1.1.1`** — würde fail-closed-Prinzip brechen. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-002 — IPv6 v4-only](002-ipv6-homelab-v4-only.md) — Netzwerk-Grundkonfiguration, Blocky AAAA-Filter
- [ADR-003 — OOM-Isolation](003-oom-cgroup-isolation.md#tier-modell) — Technitium/DNS als Tier-0-Dienst
- [ADR-005 — Restart=always](005-critical-systemd-restart.md) — DNS-Ausfall löst Restart aus
- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — Firewall-Regeln die funktionierendes DNS voraussetzen
- [GUIDE-network-database.md — Blocky](../guides/GUIDE-network-database.md#blocky) — Betriebsguide für Blocky als LAN-DNS und DoT-Resolver
