---
meta:
  role: doc
  purpose: Pocket-ID als OIDC/Passkey Provider — Entscheidung gegen Authentik/Keycloak
  status: accepted
  date: 2026-07-05
  error_pattern: "pocket-id.*failed|ENCRYPTION_KEY.*not set|invalid.*encryption.key"
  quick_fix: "ENCRYPTION_KEY in /var/lib/secrets/pocket-id.env prüfen; systemctl restart pocket-id"
  services: [pocket-id]
  betrifft:
    - modules/10-network/17-pocket-id.nix
    - machines/q958/media-secrets.nix
    - machines/q958/profile.local.nix
  docs:
    - docs/guides/GUIDE-auth-stack.md
    - docs/guides/GUIDE-security-secrets.md
    - docs/adr/2024-systemd-creds-tpm.md
  tags:
    - auth
    - oidc
    - pocket-id
    - passkeys
---

# ADR-1025: Pocket-ID als OIDC/Passkey Provider

**Status:** Accepted
**Datum:** 2026-07-05

---

## Kontext

q958 benötigt einen zentralen Identity Provider für SSO über alle Browser-zugänglichen
Dienste (Jellyfin, *arr, Paperless, n8n, Vaultwarden etc.). Anforderungen:

- Passkey-native (YubiKey, FaceID, TouchID als primäre Auth-Methode)
- Kein eigenes LDAP/ActiveDirectory — keine User-Verwaltung außer handvoll lokaler Accounts
- Deklarativ konfigurierbar via Environment Variables (Nix-first)
- Single Go Binary, kein JVM/Python/Ruby-Stack
- Secrets via `*_FILE`-Pattern kompatibel mit systemd `LoadCredential`
- Lightweight genug für Homelab (< 100 MB RAM idle)

## Entscheidung

**Pocket-ID** wird als einziger OIDC Provider auf q958 eingesetzt.

Modul: `modules/10-network/17-pocket-id.nix`
Port: 1411 (aus `my.ports.pocket-id`)
State: `/var/lib/pocket-id` (SQLite Default)

## Warum nicht die Alternativen?

| Alternative | Ablehnungsgrund |
|-------------|-----------------|
| **Authentik** | Python + PostgreSQL + Redis + Worker = 4 Prozesse, ~500 MB RAM. Overkill für Homelab. |
| **Keycloak** | JVM, komplexes Admin-UI, LDAP-first Design. Konfiguration nicht rein env-var-basiert. |
| **Authelia** | Kein Passkey-Support (nur TOTP/WebAuthn). Proximally gut, aber hinter Pocket-ID bei Passkeys. |
| **Kanidm** | Rust, modern, aber erzwingt eigenes LDAP-Schema. Für 5 User überdimensioniert. |
| **Dex** | Nur Connector, kein eigener Identity Store. Braucht dahinter noch eine User-DB. |

## Konfigurationsschnittstelle (aus forensischer Analyse)

Pocket-ID wird **ausschließlich über Environment Variables** konfiguriert. Keine config.yaml.

Kritische Variablen:

| Variable | Wert auf q958 | Notiz |
|----------|---------------|-------|
| `PORT` | `1411` | Default, aus Port-Registry |
| `APP_URL` | `https://auth.<domain>` | Public-facing URL **und** OIDC Issuer — NixOS: `services.pocket-id.settings.APP_URL` (nicht `PUBLIC_URL`!) |
| `ENCRYPTION_KEY` | via `secretsFile` / Stufe 9: `LoadCredential` | Pflicht — verschlüsselt OIDC Client Secrets in DB |
| `ENCRYPTION_KEY_FILE` | Stufe 9: `$CREDENTIALS_DIRECTORY/pocket_id_key` | Für systemd-creds |
| `TRUST_PROXY` | `true` | Caddy als Reverse Proxy |
| `STATIC_API_KEY` | optional | Für API-basierte OIDC-Client-Provisionierung |
| `DB_CONNECTION_STRING` | `/var/lib/pocket-id/pocket-id.db` | Absoluter Pfad (kein Docker-WORKDIR) |

`*_FILE`-Support offiziell dokumentiert für:
- `ENCRYPTION_KEY_FILE`
- `MAXMIND_LICENSE_KEY_FILE`
- `SMTP_PASSWORD_FILE`
- `LDAP_BIND_PASSWORD_FILE`

## OIDC-Clients: Provisionierung

OIDC-Clients können **nicht** dateibasiert beim Start provisioniert werden — nur via Web-UI
oder API (mit `STATIC_API_KEY`-Header).

Workflow:
1. Pocket-ID starten (Web-UI auf `auth.<domain>`)
2. OIDC Client anlegen: Name, Redirect-URIs, PKCE
3. Client-ID + Secret notieren → in `profile.local.nix` eintragen (Dev) / `LoadCredential` (Prod)

Für OAuth2-Proxy (forward-auth):
```
Client-ID: oauth2-proxy
Redirect-URI: https://<proxy-domain>/oauth2/callback
Scopes: openid profile email
```

## Hardening (NixOS-Modul)

Das Modul `17-pocket-id.nix` setzt:
- `ProtectSystem = "strict"` + `ProtectHome = true`
- `NoNewPrivileges`, `PrivateTmp`, `PrivateDevices`
- `ProtectKernelTunables/Modules/ControlGroups`
- `RestrictNamespaces/Realtime/SUIDSGID`
- `LockPersonality`
- `ReadWritePaths = [ dataDir ]` — nur `/var/lib/pocket-id` schreibbar

## Konsequenzen

- Alle SSO-Flows gehen über `auth.<domain>` (Pocket-ID)
- Jellyseerr ist **Ausnahme**: nutzt Jellyfin-eigene Auth, kein OIDC (→ GUIDE-auth-stack.md)
- Stufe 9: `ENCRYPTION_KEY` via `LoadCredential` aus systemd-creds (→ ADR-2024)
- OIDC-Client-Provisioning ist manuell (Web-UI) — kein deklarativer Dateimechanismus

## Debugging: OIDC Issuer mismatch {#app-url-bug}

**Symptom:** oauth2-proxy oder andere OIDC-Clients melden:
```
oidc: issuer did not match the issuer returned by provider
expected "https://auth.<domain>" got "http://localhost"
```

**Ursache:** `PUBLIC_URL` existiert nicht als Pocket-ID-Konfigurationsvariable.
Die OIDC Issuer URL wird durch `APP_URL` gesetzt.

**Fix (NixOS):**
```nix
services.pocket-id.settings.APP_URL = "https://auth.${domain}";
# Nicht: environment.extraEnv.PUBLIC_URL = ...
```

Nach Änderung: `sudo systemctl restart pocket-id`

**Verifikation:**
```bash
curl -s https://auth.<domain>/.well-known/openid-configuration | grep '"issuer"'
# Muss "https://auth.<domain>" ausgeben, nicht "http://localhost"
```

## Siehe auch

- [GUIDE-auth-stack.md](../guides/GUIDE-auth-stack.md) — Auth-Matrix, OIDC-Clients, OAuth2-Proxy
- [ADR-1033 — oauth2-proxy](1033-oauth2-proxy-forward-auth.md) — Forward-Auth Setup + alle oauth2-proxy Bugs
- [ADR-2024 — systemd-creds](2024-systemd-creds-tpm.md) — wie ENCRYPTION_KEY in Stufe 9 läuft
- [ADR-1019 — UDS-First](1019-uds-first-philosophy.md) — Pocket-ID über TCP (kein UDS-Support)
