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
    - modules/10-network/1090-host-network.nix
    - lib/services-spec.nix
  docs:
    - docs/adr/1031-caddy-zones-konzept.md
    - docs/adr/7005-cloudflare-dns-acme-ddns.md
    - docs/adr/1014-caddy-security-headers-trusted-proxies.md
---

# Design: Cloudflare-Proxy-Ableitung aus Caddy-Zonen

**Status:** accepted  
**Datum:** 2026-07-10  
**Betrifft:** `secrets.nix`, `1090-host-network.nix`

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
# $domain kommt aus dem Nix-String-Interpolation des Provision-Scripts (ddnsFqdn aus profile.nix)
jq -n --arg zone_id "$ZONE_ID" --arg token "$TOKEN" --arg domain "$DOMAIN" \
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

### 2. `modules/10-network/1090-host-network.nix`

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

**Nebeneffekt:** Mit `trusted_proxies` sehen CrowdSec und der DSGVO-Accesslog für
`external`-Services die echten Nutzer-IPs (aus `CF-Connecting-IP`), nicht mehr die
CF-Datacenter-IPs. CrowdSec-Bans treffen jetzt den richtigen Angreifer.

### 3. `lib/services-spec.nix`, `lib/caddy-snippets.nix`, Blocky

Keine Änderungen nötig.

---

## Sicherheitsanalyse: `trusted_proxies` trifft `private_admin`

Das ist der sicherheitskritische Kern — hier ist der vollständige Beweis, dass
die globale `trusted_proxies`-Erweiterung die `private_admin`-Schutzmechanik
**nicht beschädigt**:

**Caddy `remote_ip` vs. `client_ip`:**

```
(private_admin) {
  @external not remote_ip ${privateCidr} 127.0.0.0/8 ::1/128 ${lanCidr}
  respond @external "Forbidden" 403
}
```

- `remote_ip` = direkte TCP-Verbindungs-IP (Layer 4, nicht manipulierbar über Header)
- `client_ip` = aus `X-Forwarded-For`/`CF-Connecting-IP` aufgelöste IP (Header-basiert)

`trusted_proxies` beeinflusst nur `client_ip`. `private_admin` nutzt `remote_ip`.

**Warum das für internal-Zone sicher ist:**
- `internal`-Records sind `proxied: false` → keine CF-Zwischenschicht
- Caddy sieht immer die direkte TCP-Peer-IP (LAN-IP oder Netbird-IP)
- `private_admin` prüft genau diese direkte IP → funktioniert korrekt

**Warum `private_admin` NICHT auf `client_ip` umgestellt werden darf:**
Wäre `private_admin` auf `client_ip` umgestellt, würde es `X-Forwarded-For`-Header lesen.
Ein Angreifer könnte dann `X-Forwarded-For: 192.168.1.1` mitschicken und `private_admin`
potentiell umgehen. Die direkte TCP-IP (`remote_ip`) ist Header-immun — das ist die
sichere Wahl.

**`block_scanners` (caddy-snippets.nix) nutzt ebenfalls `remote_ip`** — gleiche
Garantie, gleicher Schutz. Keine Änderung nötig.

**Implementierungspflicht:** Vor dem Merge verifizieren: `remote_ip` in der
laufenden Caddy-Version verhält sich wie dokumentiert (direkte TCP-IP).
Check: `caddy version` + [Caddy-Docs](https://caddyserver.com/docs/caddyfile/matchers#remote_ip).

---

## Operative Voraussetzungen (außerhalb NixOS-Scope)

Diese müssen im CF-Dashboard gesetzt sein — NixOS kann das nicht erzwingen:

| Einstellung | Wert | Wo | Warum |
|-------------|------|----|-------|
| SSL/TLS-Modus | **Full (strict)** | CF Dashboard → SSL/TLS | "Flexible" = CF→Origin unverschlüsselt + Redirect-Loops |
| ACME-Challenge | **DNS-01** | bereits aktiv via CF-Token | HTTP-01 funktioniert nicht hinter CF-Proxy (oranges Wolken-Icon) |

**CF SSL/TLS prüfen:**  
CF Dashboard → Domain → SSL/TLS → Overview → Encryption mode = "Full (strict)"  
(Abschnitt gilt für alle proxied Records — einmal setzen, gilt für die Zone)

---

## Was gleichbleibt und warum

**Blocky `customDNS`:** Blockt bereits zone-basiert — `<domain> = <lanIP>`
matched ALLE Subdomains für LAN-Clients. LAN-Clients gehen nie durch CF-Proxy, egal
ob CF-Record proxied oder nicht. Das ist kein Problem, sondern ein Feature — aber wir
verlassen uns im Design nicht darauf (KISS).

**`private_admin`:** Unverändert. Greift weiterhin für `internal`-Zone korrekt, weil
der Traffic nie durch CF läuft.

**ddns-updater:** Aktualisiert alle Records (Wildcard + External-Einzelrecords) wenn
sich die öffentliche IP ändert. Konsistenz gesichert.

---

## Debugging-Schnellreferenz

Alle Befehle setzen `DOMAIN` und `LANIP` zu Beginn aus der NixOS-Config — einmal
ausführen, dann alle Befehle darunter kopieren:

```bash
# Variablen aus NixOS-Config lesen (einmalig am Session-Start)
DOMAIN=$(sudo nix eval --raw /etc/nixos#nixosConfigurations.q958.config.my.configs.identity.domain)
LANIP=$(sudo nix eval --raw /etc/nixos#nixosConfigurations.q958.config.my.configs.server.lanIP)
CFTOKEN=$(cat /var/lib/secrets/cloudflare_api_token)
```

### Verbindungsproblem: "Komme nicht auf Service X drauf"

```bash
# 1. Welche Zone hat der Service?
grep -A5 "serviceName" /etc/nixos/lib/services-spec.nix

# 2. Welche IP bekommt der Client?
dig subdomain.$DOMAIN +short
# → $LANIP     = direkte Verbindung (unproxied oder LAN via Blocky) ✓
# → 104.16.x.x = CF-Proxy aktiv (erwartet für external-Zone)
# → 104.16.x.x bei internal/streaming-Zone → Problem! Record ist proxied

# 3. Was sieht Caddy als Client-IP?
sudo journalctl -u caddy -n 50 --no-pager | grep subdomain
# → "remote_ip":"192.168.x.x"  → LAN direkt ✓
# → "remote_ip":"104.16.x.x"   → CF-IP, trusted_proxies greift nicht → Problem!
# → "remote_ip":"1.2.3.4"      → echte Internet-IP (via CF-Header extrahiert) ✓

# 4. CF-Record-Status prüfen (alle A-Records mit Proxy-Status)
ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CFTOKEN" | jq -r '.result[0].id')
curl -sf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&per_page=50" \
  -H "Authorization: Bearer $CFTOKEN" \
  | jq '.result[] | {name: .name, proxied: .proxied, content: .content}'
```

### Problem: "private_admin gibt 403, obwohl ich im LAN bin"

```bash
# LAN-Client: direkte Verbindung prüfen (muss LAN-IP zeigen, NICHT CF-IP)
dig subdomain.$DOMAIN +short
# Erwartet: $LANIP — wenn CF-IP kommt → Blocky läuft nicht oder Client nutzt anderen DNS
sudo systemctl status blocky

# Blocky-Antwort testen (von der Server-Console, simuliert LAN-DNS)
dig @127.0.0.53 subdomain.$DOMAIN +short
# → sollte $LANIP zurückgeben
```

### Problem: "Streaming ruckelt / bricht ab"

```bash
# Streaming-Records müssen UNPROXIED sein
for sub in jellyfin music audiobookshelf; do
  ip=$(dig $sub.$DOMAIN +short | head -1)
  echo "$sub.$DOMAIN → $ip"
done
# Erwartet: alle zeigen $LANIP, NICHT 104.16.x.x (CF)
# Wenn CF-IP → Record ist proxied → secrets-provision neu starten + ddns-updater restart
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

# 4. End-to-end: Service von außen erreichbar? (DOMAIN aus Schritt oben)
curl -sv https://auth.$DOMAIN/health 2>&1 | grep -E "< HTTP|Connected to"
```

---

## Bekannte Einschränkungen

- **CF-IP-Ranges können sich ändern.** CF gibt Änderungen bekannt, passiert selten.
  Beim Update: `trusted_proxies` in `1090-host-network.nix` anpassen, rebuild.
  Check: https://www.cloudflare.com/ips-v4 vs. aktuelle Config.

- **Wildcard macht internal-Services WAN-DNS-sichtbar.** Der Wildcard-Record bedeutet,
  dass `grafana.domain`, `dns.domain` etc. per DNS auflösbar und damit von außen
  erreichbar sind — nur `private_admin` blockt dann den Zugang. Das ist Status Quo
  und kein Rückschritt, aber `private_admin` ist der einzige Gate.

  **Härtere Alternative:** Wildcard entfernen, `streaming`-Services bekommen eigene
  unproxied Records (wie `external` proxied Records bekommt). Dann ist `internal`
  wirklich WAN-DNS-unsichtbar. Kosten: Netbird-Clients ohne Blocky als DNS-Resolver
  können `internal`-Services nicht mehr auflösen. Für Homelab akzeptabel so wie es ist;
  Option offen wenn Sicherheitsanforderungen steigen.

- **Netbird-DNS:** Netbird-Clients nutzen ggf. ihren eigenen DNS, nicht Blocky.
  Für `internal`-Services ist das unproblematisch (CF-Record unproxied → Caddy sieht
  Netbird-IP direkt → `private_admin` erlaubt `100.64.0.0/10`). Für `external`-Services
  mit Netbird: CF-Proxy aktiv, SSO auth — funktioniert unabhängig von IP.

---

## Implementierungsreihenfolge

1. `1090-host-network.nix` — `trusted_proxies` erweitern
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
