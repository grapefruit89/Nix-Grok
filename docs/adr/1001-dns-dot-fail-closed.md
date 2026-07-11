---
meta:
  role: doc
  purpose: ADR-1001 DNS-over-TLS, resolved→DoT direkt (Host), Blocky für LAN
  status: accepted
  date: 2026-06-17
  error_pattern: "SERVFAIL|failed to resolve|no such host|blocky.*not reachable|connection refused.*1002"
  quick_fix: "resolvectl status; dig cloudflare.com +short; systemctl restart blocky"
  services: [blocky, systemd-resolved]
  betrifft:
    - machines/q958/profile.nix
    - machines/q958/network.nix
    - modules/10-network/1090-host-network.nix
    - modules/10-network/1002-blocky.nix
  docs:
    - docs/adr/README.md
    - docs/adr/1002-ipv6-homelab-v4-only.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/2008-nftables-l4-hardening.md
  tags:
    - adr
    - dns
    - dot
    - blocky
---

# ADR-1001: DNS-over-TLS, resolved→DoT direkt {#adr-1001}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Letzte Änderung** | 2026-07-06 (Blocky ersetzt Technitium — deklarativ, stateless, ad-blocking) |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Homelab braucht DNS für Host und optional LAN.
- WAN-DNS soll **nicht** im Klartext das Internet verlassen.
- Regressionen (jemand trägt `1.1.1.1` in `nameservers`) passierten in der Vergangenheit via `resolvconf` und stale `/etc/resolv.conf`.
- Caddy ACME/DNS-Challenges und alle Host-Lookups hängen an funktionierendem DNS.
- LAN-Clients brauchen Split-Horizon (*.domain → LAN-IP) und Ad-Blocking.
- Der LAN-DNS-Resolver soll **vollständig deklarativ** konfigurierbar sein — kein imperativer API-Configure-Service.

## Entscheidung {#entscheidung}

### Aktuelle Architektur: Two-Tier {#two-tier}

```text
HOST-DNS:
  systemd-resolved → DoT direkt (8 Server aus my.configs.network.dnsBootstrap)
  /etc/resolv.conf → 127.0.0.53 (resolved stub)
  networking.nameservers = []   ← kein Blocky auf dem Host

LAN-CLIENTS:
  → Blocky (LAN-IP:53)
  → Blocky leitet weiter zu DoT (deklarativ in services.blocky.settings)
  → Blocky blockt Ads via Hagezi-Blockliste + /home/moritz/blocky-allowlist.txt

HOST split-horizon:
  networking.extraHosts → /etc/hosts (deklarativ, NSS vor DNS)
  Jeder Dienst aus services.spec bekommt automatisch einen Eintrag.

LAN split-horizon:
  Blocky customDNS.mapping: *.domain → LAN-IP (deklarativ in 1002-blocky.nix)
```

### Implementierungsdetails {#implementierung-details}

1. **systemd-resolved** — `DNSOverTLS=yes` (strict, kein Plaintext-Fallback).
   Konfiguration aus `my.configs.network.dnsBootstrap` (SSoT in `profile.nix`).
   Format: `IP#TLS-Hostname` (resolved-Format).

2. **networking.nameservers = []** — leer. Externe Einträge würden `/etc/resolv.conf` überschreiben
   und DoT umgehen. Build-Assertion bricht wenn nicht leer.

3. **networking.resolvconf.enable = false** — resolved verwaltet `/etc/resolv.conf` allein.

4. **Blocky DNS** — nur für LAN-Clients. Port 53 (DNS) auf LAN-IP, Port 1002 (HTTP/Prometheus).
   DoT-Forwarder: deklarativ via `services.blocky.settings.upstreams.groups.default`.
   Ad-blocking: Hagezi multi-Blockliste, tägliche Updates, Allowlist `/home/moritz/blocky-allowlist.txt`.

5. **networking.extraHosts** — `/etc/hosts`-Einträge für split-horizon auf dem Host.
   Generiert aus `config.my.services.spec` (alle Dienste mit `subdomain != null`).
   NSS-Reihenfolge: `/etc/hosts` kommt vor DNS — kein NAT-Hairpin-Problem.

## Diagnose {#diagnose}

**Host-DNS prüfen (resolved):**
```bash
resolvectl status                          # DNS-Server + DNSOverTLS-Status
dig cloudflare.com +short                  # via 127.0.0.53 → resolved → DoT
cat /etc/resolv.conf                       # Muss: nameserver 127.0.0.53
```bash

**Blocky (LAN-DNS):**
```bash
systemctl status blocky --no-pager
dig @192.168.2.73 cloudflare.com +short   # direkt gegen Blocky (LAN-IP)
journalctl -u blocky -n 30 --no-pager | grep -iE "error|fail|warn"
curl -s http://127.0.0.1:1002/metrics | grep blocky_query  # Prometheus-Metriken
```

**Split-Horizon Host:**
```bash
getent hosts sonarr.nix.m7c5.de           # muss LAN-IP zurückgeben (via /etc/hosts)
grep "nix.m7c5.de" /etc/hosts             # alle generierten Einträge
```bash

## Fix {#fix}

```bash
# 1. Host-DNS weg — resolved neustarten {#1-host-dns-weg-resolved-neustarten}
sudo systemctl restart systemd-resolved
resolvectl status

# 2. Blocky neustart (LAN-DNS weg, Blockliste fehlt, etc.) {#2-blocky-neustart-lan-dns-weg-blockliste-fehlt-etc}
sudo systemctl restart blocky
systemctl status blocky

# 3. Build-Assertions prüfen {#3-build-assertions-pruefen}
grep -r "nameservers" /etc/nixos/machines/q958/
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- **Kein Chicken-Egg-Problem** — Host-DNS über resolved, unabhängig von Blocky.
- Blocky-Ausfall betrifft **nur LAN-Clients**, nicht den Host selbst.
- Split-Horizon HOST ist 100% deklarativ (`/etc/hosts`, NSS-Ebene).
- LAN split-horizon und DoT-Forwarder sind **vollständig deklarativ** in Nix — kein API-Configure-Service.
- Blocky blockt Ads für alle LAN-Clients (Hagezi multi-Blockliste).
- Prometheus-Metriken auf Port 1002 — Grafana-Integration möglich.

### Negativ / Trade-offs {#negativ}

- Kein Web-UI für Blocky (nur Prometheus-Metriken + Logs).
- LAN-Clients nutzen Blocky nur, wenn Fritzbox/DHCP DNS auf `192.168.2.73` zeigt.
- Zwei DNS-Pfade (resolved + Blocky) statt einer einheitlichen Kette.

## Implementierungs-Schichten {#implementierung}

| Schicht | Datei |
|---------|-------|
| Daten / DoT-Server | `machines/q958/profile.nix` (`network.dns.bootstrap`) |
| Verdrahtung | `machines/q958/network.nix` |
| Modul Host-DNS | `modules/10-network/1090-host-network.nix` |
| Modul Blocky LAN-DNS | `modules/10-network/1002-blocky.nix` |
| Host split-horizon | `networking.extraHosts` (in 1090-host-network.nix, aus services.spec) |

## Verifikation {#verifikation}

```bash
resolvectl status | grep -E "DNS Servers|DNSOverTLS"  # resolved → DoT-Server, strict
cat /etc/resolv.conf                                   # nameserver 127.0.0.53
dig cloudflare.com +short                              # Host-DNS via resolved
dig @192.168.2.73 cloudflare.com +short               # LAN-DNS via Blocky
getent hosts sonarr.nix.m7c5.de                       # split-horizon via /etc/hosts
systemctl is-active blocky                             # active
```bash

## Alternativen verworfen {#alternativen}

- **Technitium als LAN-DNS** — Web-UI, Blocklisten, Split-Horizon. Benötigt imperativen API-Configure-Service (`technitium-dns-configure`) für DoT-Forwarder und Zonen. API-Aufruf mit hartkodierten Credentials — Passwortänderung bricht Konfiguration lautlos. Komplex, stateful, 500MB RAM. Durch Blocky ersetzt (2026-07-06).
- **Technitium als einziger Host-DNS-Resolver** — Chicken-Egg-Problem: falls Technitium beim Boot
  nicht erreichbar ist, hat der Host kein DNS. Ersetzt durch resolved→DoT direct für Host.
- **Dummy-Interface split0** — LAN-DNS lauschte auf eigenem Interface, LAN-Traffic lief über
  einen extra Kernel-Bridge. Komplizierter und fragil. Ersetzt durch `/etc/hosts` (NSS-Level).
- **Marker-Datei für Idempotenz** — Systemd-State-Datei signalisierte Konfiguration abgeschlossen.
  Ersetzt durch deklarative Blocky-Konfiguration (stateless by design).
- **Klartext-DNS** — kein DoT, Traffic für Provider sichtbar. Abgelehnt.
- **Fallback auf `1.1.1.1`** — würde fail-closed-Prinzip für Klartext-DNS brechen. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-1002 — IPv6 v4-only](1002-ipv6-homelab-v4-only.md) — Netzwerk-Grundkonfiguration
- [ADR-003 — OOM-Isolation](003-oom-cgroup-isolation.md#tier-modell) — OOM-Prioritäten
- [ADR-005 — Restart=always](005-critical-systemd-restart.md) — DNS-Ausfall löst Restart aus
- [ADR-2008 — nftables L4-Härtung](2008-nftables-l4-hardening.md) — Firewall-Regeln die funktionierendes DNS voraussetzen
