---
meta:
  role: doc
  purpose: Auth-Stack — Pocket-ID, OAuth2-Proxy, Caddy forward_auth, Jellyfin-Client-Split, Jellyseerr
  docs:
    - docs/adr/025-pocket-id-oidc-provider.md
    - docs/adr/014-caddy-security-headers-trusted-proxies.md
    - docs/adr/019-uds-first-philosophy.md
    - docs/guides/GUIDE-security-secrets.md
  tags:
    - auth
    - oidc
    - pocket-id
    - oauth2-proxy
    - jellyfin
    - jellyseerr
    - caddy
---

# Auth Stack Guide {#guide-auth-stack}

> Pocket-ID (Passkey-OIDC) + OAuth2-Proxy (forward_auth) + Jellyfin-Client-Split.
> Jellyseerr ist die einzige Ausnahme: Jellyfin-Auth statt OIDC.

---

## Auth-Matrix {#auth-matrix}

| Dienst | LAN | WAN | Mechanismus |
|--------|-----|-----|-------------|
| *arr, Paperless, n8n, Vaultwarden, … | Pocket-ID SSO | Pocket-ID SSO | Caddy `import sso_auth` |
| **Jellyfin Browser** | Pocket-ID SSO | Pocket-ID SSO | Caddy `import sso_auth` + Jellyfin-Login |
| **Jellyfin Apps** (Fire TV, iOS, Android) | Jellyfin-Login | Jellyfin-Login | `X-Emby-Authorization` → kein `forward_auth` |
| `auth.*` (Pocket-ID selbst) | direkt | direkt | Kein forward_auth — sonst Deadlock |
| **Jellyseerr** | Jellyfin-Auth | Jellyfin-Auth | Kein OIDC — Jellyfin-eigene Session |
| Gatus, Grafana, SABnzbd | Tailscale/LAN only | 403 | nftables / Caddy `tailscale_admin` |

---

## Pocket-ID {#pocket-id}

Passkey-nativer OIDC Provider. Single Go Binary, ~30 MB RAM idle.
Entscheidung: [ADR-025 — Pocket-ID als OIDC Provider](../adr/025-pocket-id-oidc-provider.md).

### Konfiguration {#pocket-id-config}

Modul: `modules/10-network/17-pocket-id.nix`
Canonical URL: `https://auth.<domain>` — **kein** `forward_auth` auf diesem vHost (Deadlock).

Pflicht-Secrets:
- Dev (Stufe < 9): `ENCRYPTION_KEY` in `/var/lib/secrets/pocket-id.env`
- Production (Stufe 9+): `LoadCredentialEncrypted=pocket_id_key:…` → `ENCRYPTION_KEY_FILE=$CREDENTIALS_DIRECTORY/pocket_id_key`

```bash
# Status prüfen
systemctl status pocket-id
journalctl -u pocket-id -n 30

# API-Key-Test (STATIC_API_KEY gesetzt?)
curl -H "X-Api-Key: $STATIC_API_KEY" http://127.0.0.1:1411/api/v1/application-configuration
```

### OIDC-Clients anlegen {#oidc-clients}

Kein dateibasierter Mechanismus — nur Web-UI oder API:

**Web-UI:** `https://auth.<domain>` → Settings → OIDC Clients → New Client

**API (mit STATIC_API_KEY):**
```bash
curl -X POST http://127.0.0.1:1411/api/v1/oidc-clients \
  -H "X-Api-Key: $STATIC_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "oauth2-proxy",
    "redirectUris": ["https://auth.<domain>/oauth2/callback"],
    "allowedScopes": ["openid", "profile", "email"]
  }'
```

### State & Backup {#pocket-id-state}

- Datenbank: `/var/lib/pocket-id/pocket-id.db` (SQLite)
- Uploads: `/var/lib/pocket-id/uploads/` (Logos etc.)
- OIDC-Client-Secrets: verschlüsselt in DB (via `ENCRYPTION_KEY`) — kein Plaintext auf Disk
- Impermanence: `/var/lib/pocket-id` in `my.impermanence.extraPaths` (automatisch via Modul)

**Kritisch:** Backup von `/var/lib/pocket-id/` enthält alle OIDC-Clients + Passkey-Registrierungen.

---

## OAuth2-Proxy (forward_auth) {#oauth2-proxy}

OAuth2-Proxy sitzt zwischen Caddy und Pocket-ID. Caddy ruft für jeden Request
`forward_auth` zum Proxy auf; der Proxy prüft die Session gegen Pocket-ID.

Modul: über `my.services.oauth2-proxy.enable` (aktiv ab Stufe 5).

### Caddy-Integration {#caddy-sso}

Das Snippet `import sso_auth` in `lib/caddy-snippets.nix` expandiert zu:

```caddy
forward_auth http://127.0.0.1:<oauth2-proxy-port> {
    uri /oauth2/auth
    copy_headers X-Auth-Request-User X-Auth-Request-Email
    @error status 401
    handle_response @error {
        redir * /oauth2/sign_in?rd={scheme}://{host}{uri} 302
    }
}
```

Dienste die SSO brauchen: `import sso_auth` vor `reverse_proxy`.
Dienste ohne SSO (Pocket-ID, API-Endpoints): direkt `reverse_proxy`.

### Deadlock-Schutz {#deadlock}

**Niemals** `import sso_auth` auf dem Pocket-ID-vHost selbst (`auth.<domain>`).
Sonst: OAuth2-Proxy → Pocket-ID → OAuth2-Proxy → ∞

---

## Jellyfin Client-Split {#jellyfin-split}

Jellyfin hat zwei komplett verschiedene Client-Typen auf **einer URL**:

| Client-Typ | Header | Auth-Flow |
|------------|--------|-----------|
| Browser | kein `X-Emby-Authorization` | Caddy `import sso_auth` → Pocket-ID |
| Apps (Fire TV, iOS, Android) | `X-Emby-Authorization: MediaBrowser …` | direkt `reverse_proxy` — kein forward_auth |

Caddyfile-Matcher:
```caddy
@jellyfin_client header_regexp X-Emby-Authorization (?i)MediaBrowser

handle @jellyfin_client {
    reverse_proxy http://127.0.0.1:<jellyfin-port>
}
handle {
    import sso_auth
    reverse_proxy http://127.0.0.1:<jellyfin-port>
}
```

Warum: Apps senden `X-Emby-Authorization` mit eigenem Token-Mechanismus — kein OIDC,
kein Browser-Session-Cookie. forward_auth würde Apps blockieren.

Code: `modules/50-media/51-jellyfin.nix`.

---

## Jellyseerr {#jellyseerr}

Jellyseerr ist die **einzige Ausnahme** in der Auth-Matrix: kein Pocket-ID OIDC,
sondern Jellyfin-eigene Auth-Delegation.

### Warum kein OIDC? {#jellyseerr-warum}

Jellyseerr ist eng an Jellyfin gekoppelt: User-Accounts werden aus Jellyfin importiert,
Anfragen landen in Radarr/Sonarr. Die Jellyfin-Auth-Integration ist vollständiger als
ein separates OIDC-Flow — User brauchen sowieso einen Jellyfin-Account.

### Technische Details {#jellyseerr-technik}

| Eigenschaft | Wert |
|-------------|------|
| Port | 5002 (`my.ports.jellyseerr`) |
| State | `/var/lib/seerr` |
| NixOS-Service | `services.seerr.enable` (via nixpkgs) |
| Config | Environment Variables + `CONFIG_DIRECTORY` |
| API-Zugriff | `X-Api-Key: <key>` Header |
| Healthcheck | `GET /api/v1/settings/public` (kein Auth nötig) |

### API-Key (deklarativer Zugriff) {#jellyseerr-api}

Jellyseerr generiert beim ersten Start einen zufälligen API-Key. Für deklarativen
Zugriff (Sync-Skripte, Automatisierung) kann ein fester Key gesetzt werden:

```bash
# In /var/lib/secrets/jellyseerr.env (Dev):
API_KEY=dein-langer-zufaelliger-api-key

# Zugriff:
curl -H "X-Api-Key: $API_KEY" http://127.0.0.1:5002/api/v1/settings/main
```

Nützliche Endpoints:

| Endpoint | Methode | Zweck |
|----------|---------|-------|
| `/api/v1/settings/main` | GET/POST | Hauptkonfiguration |
| `/api/v1/service/radarr` | GET | Radarr-Verbindungen abfragen |
| `/api/v1/service/sonarr` | GET | Sonarr-Verbindungen abfragen |
| `/api/v1/settings/public` | GET | Healthcheck (kein Auth) |
| `/api/v1/request` | POST | Anfrage erstellen |

### Radarr/Sonarr-Verbindung einrichten {#jellyseerr-arr}

Erfolgt ausschließlich über Web-UI (`https://seerr.<domain>`) — kein deklarativer
Dateimechanismus. Die Verbindungsdaten (URL + API-Key von Sonarr/Radarr) werden
in Jellyseerrs SQLite-DB gespeichert.

### Caddy für Jellyseerr {#jellyseerr-caddy}

Jellyseerr hat keinen Jellyfin-Client-Split (nur Browser-Zugriff vorgesehen):

```caddy
seerr.<domain> {
    import sso_auth   # Pocket-ID vor Jellyseerr-Login
    reverse_proxy http://127.0.0.1:5002
}
```

Jellyseerr prüft danach nochmal mit Jellyfin-Auth — doppelte Absicherung.

---

## Debugging {#debugging}

```bash
# OAuth2-Proxy: Session-Cookie verfolgen
journalctl -u oauth2-proxy -n 50

# Pocket-ID: OIDC-Fehler
journalctl -u pocket-id -n 50

# Jellyseerr: API-Fehler
journalctl -u seerr -n 50

# Caddy: forward_auth Logs
journalctl -u caddy | grep forward_auth
```

### Häufige Fehler {#fehler}

| Fehler | Ursache | Fix |
|--------|---------|-----|
| `401 Unauthorized` loop | `import sso_auth` auf auth.<domain> | vHost für Pocket-ID ohne sso_auth |
| Jellyfin Apps blockiert | Fehlender `@jellyfin_client`-Matcher | Matcher für `X-Emby-Authorization` prüfen |
| Jellyseerr "Unauthorized" | Jellyfin-Auth-Verbindung getrennt | Jellyfin-URL in Jellyseerr Settings prüfen |
| `ENCRYPTION_KEY not set` | pocket-id.env nicht geladen | `systemctl cat pocket-id` → EnvironmentFile prüfen |

---

## Siehe auch {#siehe-auch}

- [ADR-025 — Pocket-ID als OIDC Provider](../adr/025-pocket-id-oidc-provider.md) — Entscheidung gegen Authentik/Keycloak
- [ADR-014 — Caddy Security-Härtung](../adr/014-caddy-security-headers-trusted-proxies.md) — trusted_proxies, Security-Header
- [ADR-019 — UDS-First](../adr/019-uds-first-philosophy.md) — warum Pocket-ID + Jellyseerr über TCP (kein UDS-Support)
- [GUIDE-security-secrets.md](GUIDE-security-secrets.md) — ENCRYPTION_KEY via systemd-creds (Stufe 9)
- [GUIDE-media-stack.md](GUIDE-media-stack.md) — Jellyfin QSV, VPN-NetNS, *arr
- [RUNBOOK.md](../RUNBOOK.md) — Quick-Fix bei Auth-Ausfall
