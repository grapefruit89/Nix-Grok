---
meta:
  role: doc
  purpose: ADR-1001 DNS-over-TLS, resolved→DoT direkt (Host), Technitium nur LAN
  status: accepted
  date: 2026-06-17
  error_pattern: "SERVFAIL|failed to resolve|no such host|technitium.*not reachable|connection refused.*1002"
  quick_fix: "resolvectl status; dig cloudflare.com +short; systemctl restart technitium"
  services: [technitium, technitium-dns-configure, systemd-resolved]
  betrifft:
    - machines/q958/profile.nix
    - machines/q958/network.nix
    - modules/10-network/11-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/1002-ipv6-homelab-v4-only.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/2008-nftables-l4-hardening.md
  tags:
    - adr
    - dns
    - dot
    - technitium
---

# ADR-1001: DNS-over-TLS, resolved→DoT direkt {#adr-1001}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Letzte Änderung** | 2026-07-06 (resolved→DoT direkt, split0-Interface entfernt, /etc/hosts split-horizon) |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

## Kontext {#kontext}

- Homelab braucht DNS für Host und optional LAN.
- WAN-DNS soll **nicht** im Klartext das Internet verlassen.
- Regressionen (jemand trägt `1.1.1.1` in `nameservers`) passierten in der Vergangenheit via `resolvconf` und stale `/etc/resolv.conf`.
- Caddy ACME/DNS-Challenges und alle Host-Lookups hängen an funktionierendem DNS.
- Chicken-Egg-Problem: Technitium als einziger Host-DNS bedeutet, Technitium muss laufen bevor DNS verfügbar ist.
- Technitium braucht MemoryMax 500M als Tier-0-Dienst ([ADR-003](003-oom-cgroup-isolation.md#tier-modell)).

## Entscheidung {#entscheidung}

### Aktuelle Architektur (ab 2026-07-06): Two-Tier {#two-tier}

```
HOST-DNS:
  systemd-resolved → DoT direkt (8 Server aus my.configs.network.dnsBootstrap)
  /etc/resolv.conf → 127.0.0.53 (resolved stub)
  networking.nameservers = []   ← kein Technitium auf dem Host

LAN-CLIENTS:
  → Technitium (127.0.0.1:53 / LAN-IP:53)
  → Technitium leitet weiter zu DoT (API-konfiguriert, non-critical)

HOST split-horizon:
  networking.extraHosts → /etc/hosts (deklarativ, NSS vor DNS)
  Jeder Dienst aus services.spec bekommt automatisch einen Eintrag.

LAN split-horizon:
  Technitium-Zone (API-basiert, state-geprüft): *.domain → LAN-IP
```

### Implementierungsdetails {#implementierung-details}

1. **systemd-resolved** — `DNSOverTLS=yes` (strict, kein Plaintext-Fallback).
   Konfiguration aus `my.configs.network.dnsBootstrap` (SSoT in `profile.nix`).
   Format: `IP#TLS-Hostname` (resolved-Format).

2. **networking.nameservers = []** — leer. Externe Einträge würden `/etc/resolv.conf` überschreiben
   und DoT umgehen. Build-Assertion bricht wenn nicht leer.

3. **networking.resolvconf.enable = false** — resolved verwaltet `/etc/resolv.conf` allein.

4. **Technitium DNS Server** — nur für LAN-Clients. Web-UI, Blocklisten, Query-Log.
   DoT-Forwarder via `technitium-dns-configure` (oneshot, API-Call, state-geprüft).

5. **technitium-dns-configure** — idempotent ohne Marker-Datei. Prüft API-State:
   - Forwarder: liest aktuelle Forwarder via `GET /api/settings/get`, setzt nur wenn abweichend.
   - Zone: prüft via `GET /api/zones/list` ob Zone existiert, legt an wenn nicht.
   Technitium-Ausfall: Service warnt nach 30 Retry-Versuchen, Host-DNS läuft via resolved weiter.

6. **networking.extraHosts** — `/etc/hosts`-Einträge für split-horizon auf dem Host.
   Generiert aus `config.my.services.spec` (alle Dienste mit `subdomain != null`).
   NSS-Reihenfolge: `/etc/hosts` kommt vor DNS — kein NAT-Hairpin-Problem.

### Limitation: Technitium-Credentials {#technitium-credentials}

Das configure-Script nutzt `admin`/`admin`. Falls das Passwort im Web-UI geändert wurde,
schlägt der API-Call **lautlos** fehl (Service exitiert 0, gibt nur Warning aus).
Technitium-DoT und Zonen laufen weiter mit dem letzten Stand.

Geplante Migration: Secrets-Cred (`ROADMAP-creds-migration.md`).
Workaround: Passwort im Web-UI zurücksetzen oder DoT manuell konfigurieren (s.u.).

## Diagnose {#diagnose}

**Host-DNS prüfen (resolved):**
```bash
resolvectl status                          # DNS-Server + DNSOverTLS-Status
dig cloudflare.com +short                  # via 127.0.0.53 → resolved → DoT
cat /etc/resolv.conf                       # Muss: nameserver 127.0.0.53
```

**Technitium (LAN-DNS):**
```bash
systemctl status technitium --no-pager
systemctl status technitium-dns-configure --no-pager
dig @127.0.0.1 cloudflare.com +short      # direkt gegen Technitium
journalctl -u technitium -n 30 --no-pager | grep -iE "error|fail|warn"
```

**Split-Horizon Host:**
```bash
getent hosts sonarr.nix.m7c5.de           # muss LAN-IP zurückgeben (via /etc/hosts)
grep "nix.m7c5.de" /etc/hosts             # alle generierten Einträge
```

## Fix {#fix}

```bash
# 1. Host-DNS weg — resolved neustarten
sudo systemctl restart systemd-resolved
resolvectl status

# 2. Technitium-DoT nicht konfiguriert (nach Passwortänderung):
#    Web-UI: http://localhost:1002 → Settings → Forwarder Protocol: DNS-over-TLS
#    Forwarder: 1.1.1.1:853, 1.0.0.1:853, 9.9.9.9:853, 149.112.112.112:853, 194.242.2.2:853

# 3. Configure-Service manuell neu ausführen (wenn admin/admin noch aktiv):
sudo systemctl restart technitium-dns-configure
systemctl status technitium-dns-configure

# 4. Build-Assertions prüfen
grep -r "nameservers" /etc/nixos/machines/q958/
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- **Kein Chicken-Egg-Problem** — Host-DNS über resolved, unabhängig von Technitium.
- Technitium-Ausfall betrifft **nur LAN-Clients**, nicht den Host selbst.
- Split-Horizon HOST ist 100% deklarativ (`/etc/hosts`, NSS-Ebene).
- Technitium hat Web-UI, DNS-Blocklisten, Query-Log.
- DoT-Konfiguration ist automatisiert und idempotent (API-State, kein Marker).
- Klare Trennung: resolved = Host-DNS, Technitium = LAN-DNS.

### Negativ / Trade-offs {#negativ}

- Technitium-DoT-Forwarder sind **Runtime** (API), nicht Build-Zeit — Credentials-Abhängigkeit.
- LAN-Clients nutzen Technitium nur, wenn Fritzbox/DHCP DNS auf `192.168.2.73` zeigt.
- Zwei DNS-Pfade (resolved + Technitium) statt einer einheitlichen Kette.

## Implementierungs-Schichten {#implementierung}

| Schicht | Datei |
|---------|-------|
| Daten / DoT-Server | `machines/q958/profile.nix` (`network.dns.bootstrap`) |
| Verdrahtung | `machines/q958/network.nix` |
| Modul | `modules/10-network/11-network.nix` |
| DoT-Configure-Service | `systemd.services.technitium-dns-configure` (in 11-network.nix) |
| Host split-horizon | `networking.extraHosts` (in 11-network.nix, aus services.spec) |

## Verifikation {#verifikation}

```bash
resolvectl status | grep -E "DNS Servers|DNSOverTLS"  # resolved → DoT-Server, strict
cat /etc/resolv.conf                                   # nameserver 127.0.0.53
dig cloudflare.com +short                              # Host-DNS via resolved
dig @127.0.0.1 cloudflare.com +short                  # LAN-DNS via Technitium
getent hosts sonarr.nix.m7c5.de                       # split-horizon via /etc/hosts
# Technitium Web-UI: Settings → Forwarder Protocol = Tls
```

## Alternativen verworfen {#alternativen}

- **Technitium als einziger Host-DNS-Resolver** — Chicken-Egg-Problem: falls Technitium beim Boot
  nicht erreichbar ist, hat der Host kein DNS. Ersetzt durch resolved→DoT direct für Host.
- **Dummy-Interface split0** — Technitium lauschte auf eigenem Interface, LAN-Traffic lief über
  einen extra Kernel-Bridge. Komplizierter und fragil. Ersetzt durch `/etc/hosts` (NSS-Level).
- **Marker-Datei für Idempotenz** — Systemd-State-Datei signalisierte Konfiguration abgeschlossen.
  Ersetzt durch API-State-Check (idempotent, kein stale Marker nach Konfigurationsänderungen).
- **Blocky** — konfiguriert DoT als NixOS-Option (Build-Zeit), kein Web-UI. Ersetzt durch Technitium.
- **Klartext-DNS** — kein DoT, Traffic für Provider sichtbar. Abgelehnt.
- **Fallback auf `1.1.1.1`** — würde fail-closed-Prinzip für Klartext-DNS brechen. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-1002 — IPv6 v4-only](1002-ipv6-homelab-v4-only.md) — Netzwerk-Grundkonfiguration
- [ADR-003 — OOM-Isolation](003-oom-cgroup-isolation.md#tier-modell) — Technitium als Tier-0-Dienst
- [ADR-005 — Restart=always](005-critical-systemd-restart.md) — DNS-Ausfall löst Restart aus
- [ADR-2008 — nftables L4-Härtung](2008-nftables-l4-hardening.md) — Firewall-Regeln die funktionierendes DNS voraussetzen
- [ROADMAP-creds-migration.md](../ROADMAP-creds-migration.md) — geplante Secrets-Migration Technitium-Credentials
