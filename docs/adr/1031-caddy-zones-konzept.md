---
meta:
  role: doc
  purpose: Caddy-Zonen-Konzept — internal / external / streaming
  status: accepted
  date: 2026-07-10
  tags:
    - caddy
    - zones
    - security
    - ingress
  docs:
    - lib/caddy-ingress.nix
    - lib/caddy-snippets.nix
    - lib/services-spec.nix
    - docs/adr/1014-caddy-security-headers-trusted-proxies.md
    - docs/adr/1025-pocket-id-oidc-provider.md
    - docs/adr/1032-internal-zone-sso.md
    - docs/adr/7005-cloudflare-dns-acme-ddns.md
---

# ADR-1031: Caddy-Zonen-Konzept — internal / external / streaming {#adr-1031-caddy-zonen-konzept-internal-external-streaming}

**Status:** accepted  
**Datum:** 2026-07-05 (aktualisiert 2026-07-10)  
**Betrifft:** lib/services-spec.nix, lib/caddy-ingress.nix, lib/caddy-snippets.nix

## Kontext {#kontext}

Alle Services werden über Caddy als Reverse-Proxy exponiert. Es gibt vier Zonen, davon drei
mit Caddy-vHosts:

| Zone | Snippets | Zugang | Auth | CF-Proxy |
|------|----------|--------|------|----------|
| `loopback` | — | kein Caddy-vHost | intern only | — |
| `internal` | `private_admin` + `security_headers` | LAN + Netbird | IP-basiert (kein SSO) | egal |
| `external` | `security_headers` + `sso_auth` + `sso_redirect` | Internet + LAN | Pocket-ID SSO | proxied ✅ |
| `streaming` | `streamer_headers` + `security_headers` + `sso_auth` + `sso_redirect` | Internet + LAN | Pocket-ID SSO | **unproxied ⚠️** |

**`private_admin` (caddy-snippets.nix):** Blockiert alle IPs außerhalb von
`192.168.0.0/16`, `100.64.0.0/10` (Netbird), `127.0.0.0/8` mit HTTP 403.
Kein Credentials-Prompt, kein Redirect — harte Firewall auf Caddy-Ebene.

**`sso_auth` (caddy-snippets.nix):** `forward_auth` zu Pocket-ID (Port 1001).
Pocket-ID verifiziert das Session-Cookie. Bei fehlendem Cookie → 401.

**`sso_redirect` (caddy-snippets.nix):** `handle_errors 401 { redir ... }`.
Muss auf vHost-Ebene importiert werden, NICHT innerhalb von `handle {}` (Caddy-Limitation).

**`streamer_headers` (caddy-snippets.nix):** Setzt streaming-freundliche Response-Header.
Das eigentliche `flush_interval -1` kommt aus `caddy-ingress.nix` im `reverse_proxy`-Block.

## Entscheidung {#entscheidung}

### Zonen-Redesign 2026-07-10 {#zonen-redesign-2026-07-10}

Die ursprünglichen Zonen `family-pocketid` und `public` wurden zusammengeführt:

- `family-pocketid` → `external` (klarerer Name, gleiche SSO-Semantik)
- `public` (war immer leer) → entfernt
- `streaming` als neue eigenständige Zone für Media-Server

**Grund für eigene `streaming`-Zone** statt `external + flush_interval`-Sonderfalllogik:
Früher wurde `streamingSubdomains` als separate Liste gepflegt und ein spezieller Generator
aufgerufen. Das war implizit. Jetzt ist die Zone deklarativ in `services-spec.nix` — der
Ingress-Generator braucht keine separate Liste mehr.

**Pflicht für `streaming`-Zone: CF-DNS-Record MUSS `proxied: false` sein.**
CF puffert Response-Bodies → bricht Media-Streaming auch mit `flush_interval -1` auf Caddy-Seite.
Details: [ADR-7005 — Cloudflare](7005-cloudflare-dns-acme-ddns.md).

### Welche Services in welcher Zone? {#welche-services-in-welcher-zone}

**internal (LAN-only, `private_admin`):**
`gatus`, `scrutiny`, `grafana`, `sabnzbd`, `blocky`, `ddns-updater`,
`sonarr`, `radarr`, `readarr`, `prowlarr`, `lidarr`, `vaultwarden`, `homepage`

**external (Internet + LAN, Pocket-ID SSO):**
`pocket-id`, `seerr`, `filebrowser`, `linkwarden`, `open-webui`, `paperless`,
`home-assistant`, `zigbee-stack`, `amp`

**streaming (Internet + LAN, SSO, flush_interval=-1, CF UNPROXIED):**
`jellyfin`, `navidrome`, `audiobookshelf`

### Besondere vHosts (eigene Generatoren in caddy-ingress.nix) {#besondere-vhosts-eigene-generatoren-in-caddy-ingressnix}

| vHost | Generator | Grund |
|-------|-----------|-------|
| `auth.DOMAIN` | `genAuthVhost` | Pocket-ID braucht `/api/auth/*` und `/.well-known/*` ohne SSO |
| `jellyfin.DOMAIN` | `genJellyfinVhost` | Native Apps (Infuse, iOS) umgehen SSO via `X-Emby-Authorization` |
| `music.DOMAIN` | `genNavidromeVhost` | SubSonic-Clients nutzen `/rest/*` und `/share/*` (Token-Auth in URL) |
| `vault.DOMAIN` | `genVaultwardenVhost` | Vaultwarden hat eigenes Auth-System; kein SSO-Overlay |
| `dashboard.DOMAIN`, `amp.DOMAIN`, `home.DOMAIN`, `zigbee.DOMAIN` | `genSecurityOnlyVhost` | Security-Headers, kein SSO-Overlay |

Für Jellyfin und Navidrome überschreibt der eigene Generator die `streaming`-Zone-Logik, liefert
aber dieselben `flush_interval -1` + `streamer_headers`-Semantiken manuell.

### Netbird als LAN-Ersatz {#netbird-als-lan-ersatz}

`internal` blockiert WAN-Clients, aber Netbird-Clients haben IPs im `100.64.0.0/10`
(Netbird Overlay-Netz). Alle `internal`-Dienste sind von Netbird aus erreichbar.

## Konsequenzen {#konsequenzen}

- `services-spec.nix` ist die SSoT für Zone-Zuordnung. Neue Dienste brauchen explizite Zone.
- `caddy-ingress.nix` generiert vHosts vollständig aus Zone — kein separates Streaming-Listen-Pflegen.
- `streaming`-Zone → immer prüfen ob CF-DNS-Record `proxied: false`. Bei proxied: Streaming bricht.
- Neue WAN-Dienste brauchen explizite Begründung (Risikobewertung vor Öffnung).
- Services mit eigenem Generator ignorieren Zone-Logik für Caddy-Snippets.

## Entscheidungsmatrix für neue Dienste {#entscheidungsmatrix-fuer-neue-dienste}

| Frage | ja → | nein → |
|-------|------|--------|
| Braucht der Dienst WAN-Zugang? | `external` | `internal` |
| Streamt er Medien / Echtzeit-Audio/Video? | `streaming` + CF unproxied | bleibt in `external` |
| Hat er eigene App-Auth (kein SSO-Overlay nötig)? | `genSecurityOnlyVhost` | standard `genZoneVhost` |
| Hat er API-Endpoints die SSO umgehen müssen? | eigener `genXxxVhost` | standard |

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-05 | Initial — 3 Zonen (internal, family-pocketid, public) |
| 2026-07-10 | Redesign: family-pocketid → external; public entfernt; streaming als eigene Zone; streamingSubdomains-Liste entfernt |

## Siehe auch {#siehe-auch}

- [ADR-1034 — secrets-portal Architektur](1034-secrets-portal-architecture.md)
- [ADR-1032 — internal Zone SSO](1032-internal-zone-sso.md)
- [ADR-1033 — oauth2-proxy Forward-Auth](1033-oauth2-proxy-forward-auth.md)
- [ADR-7005 — Cloudflare DNS/ACME/DDNS](7005-cloudflare-dns-acme-ddns.md)
- [GUIDE-auth-stack](../guides/GUIDE-auth-stack.md)
- [GUIDE-cloudflare](../guides/GUIDE-cloudflare.md)
