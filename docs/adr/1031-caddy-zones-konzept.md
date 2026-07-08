---
meta:
  role: doc
  purpose: "ADR-1031: Caddy-Zonen-Konzept — internal / family-pocketid / public"
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
---

# ADR-1031: Caddy-Zonen-Konzept — internal / family-pocketid / public

**Status:** accepted  
**Datum:** 2026-07-05 (aktualisiert 2026-07-08)  
**Betrifft:** lib/services-spec.nix, lib/caddy-ingress.nix, lib/caddy-snippets.nix

## Kontext

Alle Services werden über Caddy als Reverse-Proxy exponiert. Es gibt drei Vertrauenszonen:

| Zone | Snippets | Zugang | Auth |
|------|---------|--------|------|
| `loopback` | — | Kein Caddy-vHost | intern only |
| `internal` | `private_admin` + `sso_auth` + `sso_redirect` | LAN + Netbird/Tailscale | IP-basiert + Pocket-ID SSO |
| `family-pocketid` | `sso_auth` + `sso_redirect` | WAN | Pocket-ID SSO |
| `public` | — | WAN | keine Auth |

**`private_admin` (caddy-snippets.nix):** Blockiert alle IPs außerhalb von
`192.168.0.0/16`, `100.64.0.0/10` (Netbird/Tailscale), `127.0.0.0/8` mit HTTP 403.
Kein Credentials-Prompt, kein Redirect — harte Firewall auf Caddy-Ebene.

**`sso_auth` (caddy-snippets.nix):** `forward_auth` zu Pocket-ID (Port 1001).
Pocket-ID verifiziert das Session-Cookie. Bei fehlendem Cookie → 401, der Browser
wird von Pocket-ID zur Login-Seite weitergeleitet.

**`sso_redirect` (caddy-snippets.nix):** Enthält `handle_errors 401 { redir ... }`.
Wird auf vHost-Ebene importiert (NICHT innerhalb von `handle {}` — Caddy-Einschränkung).
Nötig für oauth2-proxy-Backend; bei Pocket-ID: leer (`(sso_redirect) {}`).

## Entscheidung

### Welche Services in welcher Zone?

**internal (LAN-only + SSO):**
- `sonarr`, `radarr`, `prowlarr`, `lidarr`, `readarr` — nur intern gebraucht, kein WAN-Zugang nötig
- `vaultwarden` — Passwort-Manager, LAN/Netbird reicht (eigene App-Auth, SSO-Layer trotzdem aktiv via Zone)
- `gatus`, `scrutiny`, `grafana`, `sabnzbd`, `blocky`, `ddns-updater` — Admin-Tools

**family-pocketid (WAN mit SSO):**
- `jellyfin`, `jellyseerr`, `audiobookshelf`, `navidrome` — Medien-Streaming, WAN-Zugang gewünscht
- `pocket-id` — der SSO-Provider selbst (muss WAN erreichbar sein!)
- `homepage`, `filebrowser`, `linkwarden`, `open-webui`, `paperless`, `home-assistant`, `zigbee-stack`, `amp`

### Besondere vHosts (eigene Generatoren in caddy-ingress.nix)

| vHost | Generator | Grund |
|-------|-----------|-------|
| `auth.DOMAIN` | `genAuthVhost` | Pocket-ID braucht `/api/auth/*` und `/.well-known/*` ohne SSO |
| `jellyfin.DOMAIN` | `genJellyfinVhost` | Native Apps (Infuse, iOS) umgehen SSO via `X-Emby-Authorization` Header |
| `music.DOMAIN` | `genNavidromeVhost` | SubSonic-Clients nutzen `/rest/*` und `/share/*` (Token-Auth) |
| `vault.DOMAIN` | `genVaultwardenVhost` | Vaultwarden hat eigenes Auth-System; kein SSO-Overlay trotz `internal`-Zone |

### Netbird als LAN-Ersatz

`internal` blockiert WAN-Clients, aber Netbird-Clients haben IPs im `100.64.0.0/10`
(Netbird Overlay-Netz = selbes CIDR wie Tailscale). Damit sind alle internal-Dienste
von Netbird aus ohne VPN-Config-Aufwand erreichbar.

## Konsequenzen

- `services-spec.nix` ist die SSoT für Zone-Zuordnung. Neue Dienste müssen bewusst
  eine Zone wählen — Default ist `loopback` (kein Ingress).
- `caddy-ingress.nix` generiert automatisch die Caddyfile-Blöcke basierend auf Zone.
- `sso_redirect` muss immer auf vHost-Ebene importiert werden, nie innerhalb von
  `handle {}` (Caddy-Limitation: `handle_errors` ist kein ordered HTTP handler).
- Neue WAN-Dienste brauchen explizite Begründung (Risikobewertung vor Öffnung).
- Services mit eigenen Generatoren (`genVaultwardenVhost`, `genSecurityOnlyVhost`) ignorieren
  die Zone-basierte SSO-Logik — Zone wirkt nur auf `genZoneVhost`.

## Entscheidungsmatrix für neue Dienste

| Frage | ja → | nein → |
|-------|-------|--------|
| Braucht der Dienst WAN-Zugang? | family-pocketid | internal |
| Hat er eigene App-Auth (kein SSO-Overlay nötig)? | genSecurityOnlyVhost | standard genZoneVhost |
| Streamt er Medien? | streamingSubdomains + flush_interval | standard |
| Hat er API-Endpoints die SSO umgehen müssen? | eigener genXxxVhost | standard |
