---
meta:
  role: doc
  purpose: Cloudflare DNS, ACME DNS-01, DDNS und Token-Management für q958
  status: accepted
  date: 2026-07-09
  tags:
    - cloudflare
    - dns
    - acme
    - ddns
---

# ADR-7005: Cloudflare — DNS, ACME, DDNS und Token-Management {#adr-7005-cloudflare-dns-acme-ddns-und-token-management}

**Kontext:** Zwei Domains (moritzbaumeister.de, m7c5.de) werden über Cloudflare DNS verwaltet.
NixOS braucht einen CF-API-Token für DDNS (IP-Nachführung) und ACME DNS-01-Challenge
(Wildcard-Zertifikate). Dieser ADR dokumentiert was wie funktioniert und welche
Token-Typen es gibt.
---

## Entscheidungen {#entscheidungen}

### 1. Ein Token für DDNS + ACME, beide Zonen {#1-ein-token-fuer-ddns-acme-beide-zonen}

**Entscheidung:** Ein einzelner `cfut_`-Token deckt beide Zonen ab.

**Begründung:** Der Token hat Zone.DNS.Edit auf m7c5.de und moritzbaumeister.de —
verifiziert durch A-Record-Update (DDNS) und TXT-Record Create/Delete (ACME DNS-01).
Ein separater Token pro Domain wäre sicherer, erfordert aber Token-Management-Rechte
die unser Token nicht hat.

**Folge:** Token-Erstellung und -Rotation nur über CF-Dashboard möglich.

---

### 2. Wildcard-Records statt Einzel-Subdomains {#2-wildcard-records-statt-einzel-subdomains}

**Entscheidung:** `*.moritzbaumeister.de` und `*.m7c5.de` als einzige A-Records,
nicht proxied (grau). Keine per-Service DNS-Einträge nötig.

**Begründung:** Caddy routet nach Hostname, der Wildcard-Record reicht. Neue Services
brauchen keine CF-Änderung — einfach in NixOS hinzufügen, Caddy übernimmt.

**Ausnahme:** Der Root-Record (`moritzbaumeister.de`) ist proxied (orange) für
DDoS-Schutz der Haupt-Domain.

---

### 3. ACME via DNS-01 (kein HTTP-01) {#3-acme-via-dns-01-kein-http-01}

**Entscheidung:** `security.acme` mit Cloudflare DNS-01-Challenge via lego.

**Begründung:** Nur DNS-01 erlaubt Wildcard-Zertifikate (`*.moritzbaumeister.de`).
HTTP-01 würde pro Subdomain ein eigenes Zertifikat erfordern.

**NixOS-Mechanismus:** `security.acme.certs."moritzbaumeister.de"` mit
`dnsProvider = "cloudflare"` und CF-Token aus credstore.

---

### 4. DDNS via ddns-updater, nicht via Caddy {#4-ddns-via-ddns-updater-nicht-via-caddy}

**Entscheidung:** Separater `ddns-updater`-Service aktualisiert A-Records.

**Begründung:** Caddy hat kein eingebautes DDNS. ddns-updater ist ein fertiger,
stabiler Service der CF-API nativ unterstützt. Aktualisiert @ und * gleichzeitig.

---

## Token-Typen — kritisches Wissen {#token-typen-kritisches-wissen}

### cfut\_ — Cloudflare User Token (normaler API Token) {#cfut_-cloudflare-user-token-normaler-api-token}

Format: `cfut_<alphanumeric>`  
Verwendung: `Authorization: Bearer cfut_...`  
In profile.local.nix: `secrets.cloudflare.apiToken`  
Im MCP-Server: als Bearer-Token konfiguriert

**Kann:**
- DNS A/AAAA/TXT/CNAME Records lesen, erstellen, aktualisieren, löschen
- Beide Zonen: m7c5.de + moritzbaumeister.de
- TXT-Records für ACME DNS-01 Challenge

**Kann NICHT:**
- Andere Tokens erstellen (braucht token:edit Permission)
- Eigene Permissions auflisten (9109)
- User-Account-Info lesen (/user)

### cfk\_ — Cloudflare Origin CA Key (NICHT für DNS!) {#cfk_-cloudflare-origin-ca-key-nicht-fuer-dns}

Format: `cfk_<alphanumeric>`  
Verwendung: Nur mit Header `X-Auth-User-Service-Key`  
Nur für: `/client/v4/certificates` (Origin CA Zertifikate)

**NICHT verwechseln mit dem Global API Key oder einem normalen API Token.**  
Gibt bei Verwendung als X-Auth-Key: Error 9103 "Unknown X-Auth-Key or X-Auth-Email"  
Gibt bei Verwendung als Bearer: Error 9109 "Invalid access token"

### Global API Key — für Token-Management {#global-api-key-fuer-token-management}

Format: 37-stellige Hex-Zeichenkette ohne Präfix  
Verwendung: `X-Auth-Email + X-Auth-Key` Header  
Findet sich im CF-Dashboard: My Profile → API Tokens → API Keys → "Global API Key" → View

Kann alles inkl. Token-Erstellung. Sollte NICHT routinemäßig verwendet werden.

---

## CF-Sicherheits-Baseline (Free Tier, beide Domains) {#cf-sicherheits-baseline-free-tier-beide-domains}

Verifiziert 2026-07-09 via API. Bereits optimal konfiguriert:

| Setting | Wert |
|---|---|
| SSL/TLS Mode | `strict` |
| Security Level | `high` |
| Always Use HTTPS | `on` |
| Min TLS Version | `1.2` |
| TLS 1.3 | `on` |
| HTTP/3 (QUIC) | `on` |
| Brotli Compression | `on` |
| Automatic HTTPS Rewrites | `on` |
| Opportunistic Encryption | `on` |

**Bot Fight Mode:** Nur im CF-Dashboard setzbar, nicht via API mit unserem Token.
Manuell aktivieren: CF Dashboard → moritzbaumeister.de → Security → Bots → Bot Fight Mode = On.
Für m7c5.de wiederholen.

---

## DNS-Architektur {#dns-architektur}

```text
moritzbaumeister.de     A  93.226.213.104  proxied    (DDoS-Schutz für Root)
*.moritzbaumeister.de   A  93.226.213.104  nicht proxied  (Caddy Wildcard)

m7c5.de                 A  93.226.213.104  nicht proxied
*.m7c5.de               A  93.226.213.104  nicht proxied  (Caddy Wildcard)
*.nix.m7c5.de           A  93.226.213.104  nicht proxied  (nix-Subdomain Variante)
nix.m7c5.de             A  93.226.213.104  nicht proxied
```

DDNS-Updater hält `moritzbaumeister.de` (@  und *) automatisch aktuell.  
m7c5.de zeigt absichtlich auf den Unraid-Server — DDNS dort separat, nicht von q958 verwaltet.

---

## Neue Subdomains hinzufügen {#neue-subdomains-hinzufuegen}

**Keine CF-Aktion nötig.** Der Wildcard-Record fängt alles ab.  
Nur in NixOS: Service + Caddy-Vhost hinzufügen → `nixos-rebuild switch`.

---

## Zonen-IDs (für MCP und direkten API-Zugriff) {#zonen-ids-fuer-mcp-und-direkten-api-zugriff}

| Domain | Zone-ID |
|---|---|
| moritzbaumeister.de | `facfa2e5e9ca3f00a93e145fe7684fd1` |
| m7c5.de | `d798de6c4cb9415fc7020b7d2eb24964` |
| Account-ID | `8fcaf7ce1ca84316cba29a1b3f122ffe` |

---

## Bekannte Fallgruben (Community-Recherche 2026-07-10) {#bekannte-fallgruben-community-recherche-2026-07-10}

Aus nixpkgs-Issues und NixOS-Discourse gesammelt — betreffen uns teilweise nicht mehr
(behoben), aber relevant für Debugging und Domain-Wechsel:

| Fallgrube | Beschreibung | Unser Status |
|-----------|-------------|--------------|
| `defaults.dnsProvider` ignoriert | nixpkgs-Bug [#210807](https://github.com/NixOS/nixpkgs/issues/210807): `security.acme.defaults.dnsProvider` wird **nicht** vererbt. Ohne `dnsProvider` pro cert-Block → HTTP-Challenge-Script wird trotzdem generiert. | ✅ Wir setzen `dnsProvider` direkt im `certs.${domain}`-Block |
| `webroot`-Konflikt | Wenn `dnsProvider` gesetzt aber `webroot` nicht explizit auf `null` → "two validation methods active". | ✅ Kein `webroot` → kein Konflikt |
| Falscher Env-Var-Name | Alter Global-API-Key: `CF_API_KEY` + `CF_API_EMAIL`. Korrekter Name für Zone-Token: `CF_DNS_API_TOKEN`. | ✅ Wir nutzen `CF_DNS_API_TOKEN` |
| `dnsResolver` Pflicht | Ohne expliziten Resolver nutzt lego systemd-resolved → FORMERR oder Propagation-Fehler. Empfehlung Community: `1.1.1.1:53`. Wir brauchen `127.0.0.53:53` wegen Firewall (UDP 53 non-loopback blockiert). | ✅ `dnsResolver = "127.0.0.53:53"` |
| Secrets im Nix-Store | `pkgs.writeText` für `environmentFile` → Token world-readable im Store. Immer auf runtime-Pfad zeigen. | ✅ `/var/lib/secrets/cloudflare_acme_env` ist runtime-generiert |
| `email` Pflicht | `security.acme.defaults.email` fehlt → nicht-beschreibender Fehler. | ✅ Gesetzt via `my.security.acme.email` |

---

## Alternativen (nicht umgesetzt — Begründung) {#alternativen-nicht-umgesetzt-begruendung}

**Cloudflare Tunnel (cloudflared):**
NixOS: `services.cloudflared.tunnels`. Kein Port-Forwarding, CF übernimmt TLS.
Nicht geeignet: Streaming-Zone muss CF-unproxied sein (Tunnel = immer proxied),
`internal`-Zone soll nicht durch CF-Server gehen.

**Zwei Domains gleichzeitig aktiv:**
Aktuell nur eine "effective domain" (`profile.local.nix`). Beide parallel brauchen
zwei `security.acme.certs`-Blöcke + zwei DDNS-Konfigurationen. Nicht nötig solange
eine Domain ausreicht.

## Siehe auch {#siehe-auch}

- [ADR-1031 — Caddy-Zonen-Konzept](1031-caddy-zones-konzept.md)
- [GUIDE-cloudflare](../guides/GUIDE-cloudflare.md)
