---
meta:
  role: doc
  purpose: "Design: Cloudflare-Proxy-Ableitung aus Caddy-Zonen — welche Services CF-proxied sind und warum"
  status: accepted
  date: 2026-07-10
  tags:
    - cloudflare
    - caddy
    - dns
    - networking
    - security
  betrifft:
    - machines/q958/secrets.nix
    - modules/10-network/11-network.nix
    - lib/services-spec.nix
  docs:
    - docs/adr/1031-caddy-zones-konzept.md
    - docs/adr/7005-cloudflare-dns-acme-ddns.md
    - docs/adr/1014-caddy-security-headers-trusted-proxies.md
---

# Design: Cloudflare-Proxy-Ableitung aus Caddy-Zonen

**Status:** accepted  
**Datum:** 2026-07-10  
**Betrifft:** `secrets.nix`, `11-network.nix`

---

## Kontext und Problem

Caddy schützt interne Services mit `private_admin`: Anfragen von nicht-LAN-IPs
(`192.168.0.0/16`, `100.64.0.0/10` Netbird, `127.0.0.0/8`) werden mit HTTP 403 abgelehnt.

CF-Proxy bricht diesen Schutz: Wenn ein CF-Record `proxied: true` ist, sieht Caddy
die IP des CF-Rechenzentrums (z. B. `104.16.x.x`), nie die echte Client-IP.

```
Nutzer (LAN oder Netbird) → CF-Proxy → Caddy
                                        ↑
                              Caddy sieht CF-IP, nicht Nutzer-IP
                              private_admin: "Fremd-IP → 403" ❌
```

Das `CF-Connecting-IP`-Header (echte IP) hilft nicht: CF zeigt dort die öffentliche
Internet-IP, nicht die LAN-IP (`192.168.x.x`) oder Netbird-IP (`100.64.x.x`). LAN-Nutzer
hinter NAT kämen also auch geblockt.

**Kernkonflikt:** CF-Proxy und IP-basierte Zugriffskontrolle (`private_admin`) vertragen
sich strukturell nicht.

---

## Entscheidung

**Wildcard bleibt unproxied. Nur `external`-Zone bekommt individuelle proxied CF-Records.**

```
*.domain       → proxied: false  (Wildcard, Basis für alle Zonen)
auth.domain    → proxied: true   (external)
seerr.domain   → proxied: true   (external)
files.domain   → proxied: true   (external)
links.domain   → proxied: true   (external)
ai.domain      → proxied: true   (external)
paperless.domain → proxied: true (external)
home.domain    → proxied: true   (external)
zigbee.domain  → proxied: true   (external)
amp.domain     → proxied: true   (external)
```

Streaming- und Internal-Zone erben den Wildcard (`proxied: false`).

---

## Zonenübersicht — der mentale Anker

| Zone | CF-Record | Verbindung | Auth | Warum |
|------|-----------|------------|------|-------|
| `internal` | Wildcard (unproxied) | direkt zum Server | `private_admin` (IP) | IP-basiert — CF-Proxy würde blocken |
| `external` | Eigener Record (proxied) | → CF → Server | Pocket-ID SSO | SSO ist IP-unabhängig, CF schützt |
| `streaming` | Wildcard (unproxied) | direkt zum Server | Pocket-ID SSO | CF puffert → bricht Media-Streams |

**Faustregel:** Wenn ein Service `private_admin` oder Streaming braucht → kein CF-Proxy.

---

## Was sich ändert

### 1. `machines/q958/secrets.nix`

Im DDNS-Provision-Block (`secrets.nix` Zeile ~192): External-Zone-Subdomains als
zusätzliche `proxied: true`-Einträge in `ddns-updater-config.json`.

Die External-Subdomains (`auth`, `seerr`, `files`, `links`, `ai`, `paperless`,
`home`, `zigbee`, `amp`) werden als Nix-Liste in `secrets.nix` definiert —
entweder direkt aus `services-spec.nix` gefiltert oder als statische Liste
(beides in der Implementierung gleichwertig, da Zonen sich selten ändern).

Der jq-Block in der DDNS-Provision erhält die Liste als `--argjson`-Parameter
und generiert pro Subdomain einen proxied Record:

```bash
# Illustration — genaue Nix/Shell-Verdrahtung im Implementierungsplan
jq -n --arg zone_id "$ZONE_ID" --arg token "$TOKEN" --arg domain "moritzbaumeister.de" \
  '{settings: [
    {provider:"cloudflare", zone_identifier:$zone_id, domain:("*."+$domain), proxied:false, ttl:1, token:$token, ip_version:"ipv4"},
    {provider:"cloudflare", zone_identifier:$zone_id, domain:("auth."+$domain),      proxied:true,  ttl:1, token:$token, ip_version:"ipv4"},
    {provider:"cloudflare", zone_identifier:$zone_id, domain:("seerr."+$domain),     proxied:true,  ttl:1, token:$token, ip_version:"ipv4"}
    # ... (alle 9 external-Subdomains, in Nix via lib.map erzeugt)
  ]}'
```

Der Wildcard-Record und der Bare-Domain-Record (`moritzbaumeister.de`) bekommen
explizit `"proxied": false` (bisher nicht gesetzt, Default war ohnehin false —
jetzt zur Klarheit explizit). Der Bare-Domain-Record wird weiterhin von ddns-updater
gepflegt, hat aber keine Caddy-vHost dahinter.

### 2. `modules/10-network/11-network.nix`

`trusted_proxies` wird um CF-IPv4-Ranges erweitert. Nötig damit Caddy für
`external`-Services die echte IP aus `CF-Connecting-IP` zieht — für korrekte Logs,
Rate-Limiting, CrowdSec.

```
trusted_proxies static private_ranges
  103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
  104.16.0.0/13   104.24.0.0/14   108.162.192.0/18
  131.0.72.0/22   141.101.64.0/18 162.158.0.0/15
  172.64.0.0/13   173.245.48.0/20 188.114.96.0/20
  190.93.240.0/20  197.234.240.0/22 198.41.128.0/17
```

IPv6 weggelassen — System hat IPv6 deaktiviert.  
Aktuelle CF-IP-Liste: https://www.cloudflare.com/ips-v4

### 3. `lib/services-spec.nix`, `lib/caddy-snippets.nix`, Blocky

Keine Änderungen nötig.

---

## Was gleichbleibt und warum

**Blocky `customDNS`:** Blockt bereits zone-basiert — `moritzbaumeister.de = 192.168.2.73`
matched ALLE Subdomains für LAN-Clients. LAN-Clients gehen nie durch CF-Proxy, egal
ob CF-Record proxied oder nicht. Das ist kein Problem, sondern ein Feature — aber wir
verlassen uns im Design nicht darauf (KISS).

**`private_admin`:** Unverändert. Greift weiterhin für `internal`-Zone korrekt, weil
der Traffic nie durch CF läuft.

**ddns-updater:** Aktualisiert alle Records (Wildcard + External-Einzelrecords) wenn
sich die öffentliche IP ändert. Konsistenz gesichert.

---

## Debugging-Schnellreferenz

### Verbindungsproblem: "Komme nicht auf Service X drauf"

```bash
# 1. Welche Zone hat der Service?
grep -A5 "serviceName" /etc/nixos/lib/services-spec.nix

# 2. Welche IP bekommt der Client?
dig subdomain.moritzbaumeister.de +short
# → 192.168.2.73  = direkte Verbindung (unproxied oder LAN via Blocky)
# → 104.16.x.x    = CF-Proxy aktiv

# 3. Was sieht Caddy als Client-IP?
sudo journalctl -u caddy -n 50 --no-pager | grep subdomain
# → "remote_ip":"192.168.x.x"  → LAN direkt ✓
# → "remote_ip":"104.16.x.x"   → CF-IP, trusted_proxies greift nicht → Problem!
# → "remote_ip":"1.2.3.4"      → echte Internet-IP (via CF-Header extrahiert) ✓

# 4. CF-Record-Status prüfen (braucht CF-Token)
CFTOKEN=$(cat /var/lib/secrets/cloudflare_api_token)
ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=moritzbaumeister.de" \
  -H "Authorization: Bearer $CFTOKEN" | jq -r '.result[0].id')
# Alle A-Records mit Proxy-Status anzeigen:
curl -sf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&per_page=50" \
  -H "Authorization: Bearer $CFTOKEN" \
  | jq '.result[] | {name: .name, proxied: .proxied, content: .content}'
```

### Problem: "private_admin gibt 403, obwohl ich im LAN bin"

```bash
# LAN-Client: direkte Verbindung prüfen (muss LAN-IP zeigen, NICHT CF-IP)
dig subdomain.moritzbaumeister.de +short
# Wenn CF-IP → Blocky läuft nicht oder LAN-Client nutzt anderen DNS
sudo systemctl status blocky

# Blocky-Antwort testen (von der Server-Console, simuliert LAN-DNS)
dig @127.0.0.53 subdomain.moritzbaumeister.de +short
# → sollte 192.168.2.73 zurückgeben
```

### Problem: "Streaming ruckelt / bricht ab"

```bash
# Sicherstellen dass der Streaming-Record NICHT proxied ist
dig jellyfin.moritzbaumeister.de +short
# Muss Server-IP (keine CF-IP) sein. CF-IPs: 104.16.0.0/13, 104.24.0.0/14, etc.

# CF-Proxy-Status im CF-Dashboard oder via API (s.o.) verifizieren
# jellyfin, music, audiobookshelf → proxied: false
```

### Problem: "Logs zeigen nur CF-IPs, keine echten Nutzer-IPs"

```bash
# trusted_proxies prüfen
sudo caddy validate --config /etc/caddy/caddy.json 2>&1 | grep -i trusted
# Oder im laufenden Caddy:
sudo journalctl -u caddy -n 5 --no-pager | head -5
# CF-IPs in trusted_proxies → Caddy nutzt CF-Connecting-IP-Header
# Fehlt der CF-Range → Caddy traut dem Header nicht → zeigt CF-IP
```

### Schnellcheck nach Änderungen

```bash
# 1. Provision neu ausführen (setzt DDNS-Config)
sudo systemctl restart q958-secrets-provision
sudo journalctl -u q958-secrets-provision -n 20 --no-pager

# 2. DDNS-Updater: sofortiges Update aller Records
sudo systemctl restart ddns-updater
sudo journalctl -u ddns-updater -n 20 --no-pager

# 3. Caddy reload
sudo systemctl reload caddy
sudo journalctl -u caddy -n 10 --no-pager

# 4. End-to-end: Service von außen erreichbar?
curl -sv https://auth.moritzbaumeister.de/health 2>&1 | grep -E "< HTTP|Connected to"
```

---

## Bekannte Einschränkungen

- **CF-IP-Ranges können sich ändern.** CF gibt Änderungen bekannt, passiert selten.
  Beim Update: `trusted_proxies` in `11-network.nix` anpassen, rebuild.
  Check: https://www.cloudflare.com/ips-v4 vs. aktuelle Config.

- **Kein CF-Proxy für internal-Zone** — bedeutet: Server-IP ist für Anfragen an
  `grafana.domain`, `dns.domain` etc. im Internet sichtbar (via DNS). Wer absolute
  IP-Obfuskation will, müsste CF-Tunnel einsetzen (ADR-7005 hat das als Option notiert).
  Für Homelab akzeptabel.

- **Netbird-DNS:** Netbird-Clients nutzen ggf. ihren eigenen DNS, nicht Blocky.
  Für `internal`-Services ist das unproblematisch (CF-Record unproxied → Caddy sieht
  Netbird-IP direkt → `private_admin` erlaubt `100.64.0.0/10`). Für `external`-Services
  mit Netbird: CF-Proxy aktiv, SSO auth — funktioniert unabhängig von IP.

---

## Implementierungsreihenfolge

1. `11-network.nix` — `trusted_proxies` erweitern
2. `secrets.nix` — External-Subdomains ableiten + DDNS-Config erweitern
3. `nixos-rebuild switch`
4. `sudo systemctl restart q958-secrets-provision`
5. `sudo systemctl restart ddns-updater`
6. Verify: CF-Records per API, Logs, Erreichbarkeit

---

## Entscheidungsmatrix für neue Services

| Neuer Service braucht... | → Zone | → CF-Record |
|--------------------------|--------|-------------|
| Nur LAN/Netbird Zugang | `internal` | Wildcard (unproxied) — kein Eintrag nötig |
| Internet-Zugang, SSO | `external` | Eigener Record, `proxied: true` |
| Internet + Media-Stream | `streaming` | Wildcard (unproxied) — kein Eintrag nötig |

---

## Changelog

| Datum | Änderung |
|-------|----------|
| 2026-07-10 | Initial — Wildcard unproxied, External individuelle proxied Records |
