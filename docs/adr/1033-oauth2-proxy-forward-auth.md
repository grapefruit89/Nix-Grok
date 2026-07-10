---
meta:
  role: doc
  purpose: oauth2-proxy als OIDC Forward-Auth Gate — Bugs bei Erstinbetriebnahme und Lösungen
  status: accepted
  date: 2026-07-08
  error_pattern: "unknown flag.*--|invalid.*cookie.*secret|x509.*unknown authority|OIDC.*issuer.*mismatch|start-limit-hit"
  quick_fix: "journalctl -u oauth2-proxy -n 30; systemctl reset-failed oauth2-proxy; systemctl start oauth2-proxy"
  services: [oauth2-proxy]
  betrifft:
    - modules/20-security/28-oauth2-proxy.nix
    - machines/q958/secrets.nix
    - machines/q958/profile.local.nix
  docs:
    - docs/adr/1025-pocket-id-oidc-provider.md
    - docs/guides/GUIDE-auth-stack.md
    - docs/adr/2030-networkd-wait-online-headless.md
  tags:
    - auth
    - oidc
    - oauth2-proxy
    - forward-auth
    - sso
---

# ADR-1033: oauth2-proxy als OIDC Forward-Auth Gate {#adr-1033}

| Feld | Wert |
|------|------|
| **Status** | Accepted |
| **Datum** | 2026-07-08 |
| **Host** | q958 |

---

## Kontext {#kontext}

q958 benötigt einen Forward-Auth-Layer für Dienste ohne natives OIDC (n8n, SABnzbd, Prowlarr,
Grafana etc.). Die Auth-Entscheidung landet bei Pocket-ID ([ADR-1025](1025-pocket-id-oidc-provider.md));
Caddy leitet via `forward_auth` weiter.

oauth2-proxy Version: 7.15.2 (als NixOS-Modul via `services.oauth2-proxy`).

Die Erstinbetriebnahme produzierte **fünf verschiedene Fehler**, die alle innerhalb von
`services.oauth2-proxy` + `machines/q958/secrets.nix` entstanden. Alle sind dokumentiert,
damit sie beim nächsten Setup oder Rebuild sofort erkannt werden.

---

## Entscheidung {#entscheidung}

**oauth2-proxy im Forward-Auth-Modus (`upstream = "static://202"`)** — Caddy übernimmt das
eigentliche Proxying; oauth2-proxy prüft nur die Session und gibt `200` oder `401` zurück.

Modul: `modules/20-security/28-oauth2-proxy.nix`
Port: 4180 (Default, `http://127.0.0.1:4180`)
Mode: Auth-Only (`static://202` Upstream = statische 202-Antwort für authed Requests)

### Konfiguration (korrekte NixOS-Optionen) {#konfiguration}

```nix
services.oauth2-proxy = {
  enable = true;
  provider = "oidc";
  clientID = "placeholder";         # wird durch OAUTH2_PROXY_CLIENT_ID in keyFile überschrieben
  keyFile = "/var/lib/secrets/oauth2-proxy.env";
  redirectURL = "https://oauth.${domain}/oauth2/callback";
  oidcIssuerUrl = "https://auth.${domain}";
  upstream = "static://202";
  setXauthrequest = true;
  cookie = {
    secretFile = "/var/lib/secrets/oauth2-proxy-cookie-secret";
    domain = ".${domain}";
    secure = true;
  };
  email.domains = [ "*" ];
  reverseProxy = true;
  extraConfig = {
    "skip-provider-button" = "true";
    # DEV: minica-Zertifikat nicht in Go-Trust-Store — entfernen wenn ACME aktiv
    "ssl-insecure-skip-verify" = "true";
  };
};
```bash

### Cookie Secret generieren {#cookie-secret}

Das Cookie Secret muss **exakt 32 Bytes** sein (AES-256). Falsche Größe → Start-Fehler.

```bash
# Korrekt: 32 Chars, kein Newline {#korrekt-32-chars-kein-newline}
openssl rand -base64 24 | tr -d '\n' > /var/lib/secrets/oauth2-proxy-cookie-secret
chmod 600 /var/lib/secrets/oauth2-proxy-cookie-secret
wc -c /var/lib/secrets/oauth2-proxy-cookie-secret  # muss "32" ausgeben
```

In `secrets.nix` automatisch mit Size-Check:
```bash
if [ ! -f ${secretsDir}/oauth2-proxy-cookie-secret ] || \
   [ "$(wc -c < ${secretsDir}/oauth2-proxy-cookie-secret)" != "32" ]; then
  ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '\n' > ${secretsDir}/oauth2-proxy-cookie-secret
fi
```bash

### OIDC-Client einrichten (Pocket-ID) {#oidc-client}

```
1. https://auth.<domain> → Admin-Login (Passkey)
2. Applications → New Application
   Name: "oauth2-proxy"
   Redirect URI: https://oauth.<domain>/oauth2/callback
   PKCE: optional
3. Client-ID + Client-Secret notieren

4. profile.local.nix:
   secrets.devKeys.oauth2proxy = {
     clientId = "<client-id>";
     clientSecret = "<client-secret>";
   };

5. nixos-rebuild switch → secrets.nix schreibt oauth2-proxy.env
```yaml

---

## Bug-Dokumentation {#bugs}

### Bug 1: Falsche Flag-Namen (Underscore statt Hyphen) {#bug-flag-format}

**Symptom:**
```
oauth2-proxy[...]: unknown flag: --http_address
```text
oder
```
oauth2-proxy[...]: unknown flag: --upstreams
```text

**Ursache:** oauth2-proxy 7.x akzeptiert **ausschließlich Hyphen-Form** (`--http-address`,
`--upstream`). Underscore-Flags (`--http_address`, `--upstreams`) sind in 7.x entfernt.

Alte `extraConfig`-Einträge mit Underscore-Flags:
```nix
# FALSCH — verursacht exit code 2 (INVALIDARGUMENT): {#falsch-verursacht-exit-code-2-invalidargument}
extraConfig = {
  "http_address" = "http://127.0.0.1:4180";
  "upstreams" = [ "static://202" ];
  "set_xauthrequest" = "true";
};
```

**Fix:** NixOS-Modul-Optionen statt extraConfig verwenden:
```nix
# KORREKT: {#korrekt}
oidcIssuerUrl = "...";  # nicht "oidc_issuer_url" in extraConfig
upstream = "static://202";  # nicht "upstreams" in extraConfig
setXauthrequest = true;  # nicht "set_xauthrequest" in extraConfig
# httpAddress nicht setzen — Default "http://127.0.0.1:4180" ist korrekt {#httpaddress-nicht-setzen-default-http1270014180-ist-korrekt}
```yaml

**Merke:** Wenn extraConfig nötig: immer Hyphen-Form. Aber bevorzuge NixOS-Optionen.

---

### Bug 2: Cookie Secret falsche Größe {#bug-cookie-size}

**Symptom:**
```
oauth2-proxy[...]: cookie_secret must be 16, 24, or 32 bytes
```text

**Ursache:** `openssl rand -base64 32` erzeugt 44 Zeichen + Newline = **45 Bytes**. AES
erfordert exakt 16/24/32 Bytes.

```bash
# FALSCH — 45 Bytes: {#falsch-45-bytes}
openssl rand -base64 32 > /var/lib/secrets/oauth2-proxy-cookie-secret
wc -c  # → 45

# KORREKT — 32 Bytes, kein Newline: {#korrekt-32-bytes-kein-newline}
openssl rand -base64 24 | tr -d '\n' > /var/lib/secrets/oauth2-proxy-cookie-secret
wc -c  # → 32
```

**Diagnose bestehender Secrets:**
```bash
wc -c < /var/lib/secrets/oauth2-proxy-cookie-secret
# Wenn nicht 32: Secret regenerieren (alle Sessions werden invalidiert) {#wenn-nicht-32-secret-regenerieren-alle-sessions-werden-invalidiert}
```yaml

---

### Bug 3: TLS-Fehler — minica nicht in Go-Trust-Store {#bug-tls}

**Symptom:**
```
oauth2-proxy[...]: error redeeming code: x509: certificate signed by unknown authority
```text

**Ursache:** Wenn kein Cloudflare-API-Token gesetzt ist, stellt NixOS ACME minica-Zertifikate
aus (lokale CA). Gos Standard-Trust-Store kennt minica nicht.

**Dev-Workaround (nur ohne echte ACME-Certs):**
```nix
extraConfig."ssl-insecure-skip-verify" = "true";
```

**Entfernen wenn:** `services.my.security.acme.enable = true` UND Cloudflare-Token gesetzt →
Let's Encrypt-Certs → Go-Trust-Store vertraut ihnen.

---

### Bug 4: OIDC Issuer Mismatch — APP_URL vs PUBLIC_URL {#bug-app-url}

**Symptom:**
```text
oauth2-proxy[...]: oidc: issuer did not match the issuer returned by provider
expected "https://auth.<domain>" got "http://localhost"
```

**Ursache:** Pocket-ID verwendet `APP_URL` als OIDC Issuer URL — nicht `PUBLIC_URL`.
NixOS-Option: `services.pocket-id.settings.APP_URL`.

```nix
# FALSCH — PUBLIC_URL existiert nicht als offizielle Pocket-ID-Option: {#falsch-public_url-existiert-nicht-als-offizielle-pocket-id-option}
environment.extraEnv.PUBLIC_URL = "https://auth.${domain}";

# KORREKT — NixOS-Modul-Option: {#korrekt-nixos-modul-option}
services.pocket-id.settings.APP_URL = "https://auth.${domain}";
```bash

Nach dieser Änderung Pocket-ID neu starten:
```bash
sudo systemctl restart pocket-id
sudo systemctl reset-failed oauth2-proxy && sudo systemctl start oauth2-proxy
```

**Pocket-ID OIDC Discovery URL zum Testen:**
```bash
curl https://auth.<domain>/.well-known/openid-configuration | grep issuer
# Muss exakt "https://auth.<domain>" ausgeben (kein trailing slash, kein http://localhost) {#muss-exakt-httpsauthdomain-ausgeben-kein-trailing-slash-kein-httplocalhost}
```yaml

---

### Bug 5: start-limit-hit nach wiederholten Fehlstarts {#bug-start-limit}

**Symptom:**
```
systemd: oauth2-proxy.service: Start request repeated too quickly.
systemd: oauth2-proxy.service: Failed with result 'start-limit-hit'.
```bash

**Ursache:** Systemd lässt einen Service nach mehreren schnellen Fehlstarts nicht mehr
automatisch neu starten (Rate-Limit).

**Fix:**
```bash
sudo systemctl reset-failed oauth2-proxy
sudo systemctl start oauth2-proxy
# Ggf. zuerst secrets prüfen: {#ggf-zuerst-secrets-pruefen}
sudo systemctl start q958-secrets-provision
```

---

## Diagnose {#diagnose}

**Vollständige Diagnose-Sequenz:**

```bash
# 1. oauth2-proxy Status + letzte Fehler {#1-oauth2-proxy-status-letzte-fehler}
journalctl -u oauth2-proxy -n 50 --no-pager

# 2. Pocket-ID Status + OIDC Discovery {#2-pocket-id-status-oidc-discovery}
journalctl -u pocket-id -n 30 --no-pager
curl -s https://auth.<domain>/.well-known/openid-configuration | grep -E '"issuer"|"token_endpoint"'

# 3. Secrets prüfen {#3-secrets-pruefen}
ls -la /var/lib/secrets/oauth2-proxy*
wc -c < /var/lib/secrets/oauth2-proxy-cookie-secret  # muss 32 sein
cat /var/lib/secrets/oauth2-proxy.env  # CLIENT_ID + CLIENT_SECRET

# 4. Config prüfen (welche Flags oauth2-proxy tatsächlich bekommt) {#4-config-pruefen-welche-flags-oauth2-proxy-tatsaechlich-bekommt}
systemctl cat oauth2-proxy | grep ExecStart
```yaml

---

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Alle Dienste ohne natives OIDC können über `import sso_auth` in Caddy abgesichert werden
- Session-Cookies werden AES-256 verschlüsselt (32-Byte-Secret)
- Auth-only Mode: keine Upstream-Config nötig pro Dienst

### Negativ / Trade-offs {#negativ}

- `ssl-insecure-skip-verify = true` bleibt im Dev-Betrieb aktiv (bis ACME-Certs)
- OIDC-Client muss manuell in Pocket-ID Web-UI angelegt werden (kein Datei-Mechanismus)
- Bei Pocket-ID-Neustart: oauth2-proxy verliert OIDC-Discovery-Cache, kurzer 401-Zeitraum

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| oauth2-proxy NixOS-Modul | `modules/20-security/28-oauth2-proxy.nix` |
| Secret-Generierung | `machines/q958/secrets.nix` |
| OIDC-Client-Credentials | `machines/q958/profile.local.nix` (gitignored) |

### Verifikation {#verifikation}

```bash
# oauth2-proxy läuft und kann Auth-Requests beantworten: {#oauth2-proxy-laeuft-und-kann-auth-requests-beantworten}
systemctl is-active oauth2-proxy && curl -sI http://127.0.0.1:4180/oauth2/auth | head -3

# Pocket-ID OIDC-Issuer korrekt: {#pocket-id-oidc-issuer-korrekt}
curl -s https://auth.<domain>/.well-known/openid-configuration | grep '"issuer"'
```

---

## Alternativen verworfen {#alternativen}

- **Authelia** — Kein Passkey-Support, eigene User-DB nötig. Abgelehnt.
- **Authentik forward proxy** — Python + Redis + Celery = 3 Prozesse, ~400 MB RAM. Abgelehnt.
- **Caddy basicauth** — Kein OIDC, kein SSO, Credentials in Nix-Store. Abgelehnt.
- **extraConfig für alle Flags** — Produziert Underscore-Flag-Fehler in oauth2-proxy 7.x. Abgelehnt.

---

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-08 | Initial — alle 5 Bugs dokumentiert, Konfiguration stabilisiert |

---

## Siehe auch {#siehe-auch}

- [ADR-1031 — Caddy-Zonen-Konzept](1031-caddy-zones-konzept.md)
- [ADR-1025 — Pocket-ID als OIDC Provider](1025-pocket-id-oidc-provider.md) — IdP-Entscheidung
- [ADR-2030 — wait-online Headless](2030-networkd-wait-online-headless.md) — wait-online 2min Timeout Fix
- [GUIDE-auth-stack.md](../guides/GUIDE-auth-stack.md) — Auth-Matrix, Caddy-Integration, Debugging
