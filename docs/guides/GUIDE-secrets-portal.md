---
meta:
  role: doc
  purpose: Betriebsguide secrets-portal — Neues Secret hinzufügen, Validator erweitern
  date: 2026-07-10
  status: current
  docs:
    - docs/adr/1034-secrets-portal-architecture.md
    - packages/secrets-portal/main.go
    - modules/20-security/29-secrets-portal.nix
    - machines/q958/default.nix
  tags:
    - secrets
    - security
    - web-ui
    - how-to
---

# Guide: secrets-portal {#guide-secrets-portal}

> Einbahnstraße für Secret-Rotation im Browser. Keys rein, nie raus.
> Erreichbar unter `https://secrets.{domain}` (LAN-only).

---

## Wie ein neues Secret hinzufügen {#wie-ein-neues-secret-hinzufuegen}

**Nur eine Datei ändern:** `machines/q958/default.nix`

```nix
my.services.secrets-portal.secrets = [
  # ... bestehende Einträge ...
  {
    name = "mein_neuer_key";              # Eindeutig, snake_case — wird Dateiname in credstore
    label = "Mein Service API Key";       # Anzeigename im UI
    description = "Wofür der Key ist.";  # Kurzbeschreibung, erscheint unter Label
    link = "https://example.com/api";    # Link zur Key-Erstellungsseite (optional)
    regex = ''^[A-Za-z0-9]{32,}$'';     # Visuelles Feedback — kein Gate!
    profilePattern = ''(myApiKey\s*=\s*")[^"]*"'';  # Zeile in profile.local.nix
    # validator = { ... };               # Optionaler API-Check
  }
];
```yaml

Dann: `sudo bash scripts/nixos-rebuild-safe.sh switch`

Das Portal zeigt das neue Feld sofort — keine Code-Änderung in main.go nötig.

---

## profilePattern — wie schreibe ich das richtig? {#profilepattern-wie-schreibe-ich-das-richtig}

`profilePattern` ist ein Go-Regex mit **einer Capture-Group** die den Prefix vor dem Wert einfängt.

### String-Wert (default) {#string-wert-default}

```
Zeile in profile.local.nix:   apiToken = "";
Pattern:                       (apiToken\s*=\s*")[^"]*"
Nach Replace:                  apiToken = "neuer-wert";
```text

Der Regex matched: `apiToken = "` (Gruppe 1) + beliebiger alter Wert + `"`.
Go ersetzt durch: Gruppe 1 + neuer Wert + `"`.

**Bei nicht-eindeutigem Key-Name:** Mehr Kontext einbeziehen:
```
# Feld 'apiKey' erscheint in mehreren Sektionen — Sektion als Kontext: {#feld-apikey-erscheint-in-mehreren-sektionen-sektion-als-kontext}
profilePattern = ''(treasuremaps\.apiKey\s*=\s*")[^"]*"'';
```bash

### Bool-Wert (`profileType = "bool"`) {#bool-wert-profiletype-bool}

```
Zeile in profile.local.nix:   nixSubdomain = false;
Pattern:                       (nixSubdomain\s*=\s*)(true|false)
Nach Replace (mit "true"):     nixSubdomain = true;
```text

```nix
{
  name = "domain_nix_subdomain";
  regex = ''^(true|false)$'';
  profilePattern = ''(nixSubdomain\s*=\s*)(true|false)'';
  profileType = "bool";
}
```

### Kein profilePattern {#kein-profilepattern}

Wenn das Secret keinen Eintrag in profile.local.nix hat (z.B. ein dynamisch generierter Key):
`profilePattern` weglassen oder leer lassen. Dann wird nur in systemd-creds geschrieben.

---

## Validator-Typen {#validator-typen}

### HTTP-Validator {#http-validator}

Macht einen echten HTTP-Request mit dem Key als Auth-Header:

```nix
validator = {
  url = "https://api.example.com/v1/verify";
  header = "Authorization";       # Header-Name
  header_prefix = "Bearer ";      # Prefix vor dem Key-Wert
  method = "GET";                 # Optional, default GET
  expect_status = 200;            # Erlaubt auch 201, 202
};
```bash

### TCP-Validator (Usenet, SMTP etc.) {#tcp-validator-usenet-smtp-etc}

Für Services ohne HTTP-Endpoint — prüft ob TCP-Verbindung aufgebaut werden kann:

```nix
validator = {
  url = "tcp://news.example.com:563";
  expect_status = 0;  # 0 = TCP-Connect ausreichend, kein HTTP
};
```

### Kein Validator (Format-Only) {#kein-validator-format-only}

Für Keys ohne testbaren Endpoint (WireGuard-Key, Domainname, etc.) — Validator weglassen.
Dann gilt Regex-Match als ausreichende Prüfung, der Key wird direkt geschrieben.

---

## Häufige Regex-Patterns {#haeufige-regex-patterns}

| Key-Typ | Regex |
|---|---|
| Cloudflare Token | `^[A-Za-z0-9_-]{32,}$` |
| WireGuard PrivateKey | `^[A-Za-z0-9+/]{43}=$` |
| Domain (FQDN) | `^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z]{2,})+$` |
| S3 Repository | `^s3:` |
| AWS Key ID | `^[A-Z0-9]{16,}$` |
| UUID | `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` |
| Beliebig (min. 8 Zeichen) | *(Validator weglassen — Länge wird automatisch geprüft)* |

---

## Betrieb {#betrieb}

### Portal öffnen {#portal-oeffnen}

`https://secrets.{domain}` — nur aus dem LAN erreichbar.

### Status prüfen {#status-pruefen}

```bash
systemctl status secrets-portal
journalctl -u secrets-portal -n 30 --no-pager
```yaml

### Direkt testen (ohne Browser) {#direkt-testen-ohne-browser}

```bash
# Secrets-Liste abrufen (existiert/nicht existiert — niemals Werte) {#secrets-liste-abrufen-existiertnicht-existiert-niemals-werte}
curl --unix-socket /run/secrets-portal/secrets-portal.sock \
  http://localhost/api/secrets | python3 -m json.tool

# Key validieren {#key-validieren}
curl --unix-socket /run/secrets-portal/secrets-portal.sock \
  -X POST http://localhost/api/validate \
  -H "Content-Type: application/json" \
  -d '{"name":"cloudflare_api_token","value":"mein-token"}'

# Key siegeln (schreibt in creds + profile.local.nix) {#key-siegeln-schreibt-in-creds-profilelocalnix}
curl --unix-socket /run/secrets-portal/secrets-portal.sock \
  -X POST http://localhost/api/seal \
  -H "Content-Type: application/json" \
  -d '{"name":"cloudflare_api_token","value":"mein-token"}'
```

### Rebuild-Timer manuell auslösen {#rebuild-timer-manuell-ausloesen}

```bash
curl --unix-socket /run/secrets-portal/secrets-portal.sock \
  -X POST http://localhost/api/rebuild/now
```text

---

## Architektur auf einen Blick {#architektur-auf-einen-blick}

```
Browser (LAN-only)
  ↓ HTTPS (Caddy internal zone)
  ↓ Unix Socket /run/secrets-portal/secrets-portal.sock
Go Binary (root, ProtectSystem=strict)
  ├── POST /api/validate  → API-Call / TCP-Connect
  ├── POST /api/seal      → systemd-creds encrypt
  │                       → profile.local.nix atomar schreiben
  │                       → q958-secrets-provision restart
  │                       → Rebuild-Timer reset (3 min)
  ├── GET  /api/secrets   → exists: true|false (NIE Werte)
  └── /api/rebuild/*      → Timer steuern
```yaml

**Schlüssel-Constraint:** `/api/seal` schreibt. `/api/secrets` gibt nur Existenz zurück.
Es gibt keinen Read-Endpoint für Secret-Werte — das ist kein Bug, das ist das Design.

---

## Bekannte Einschränkungen {#bekannte-einschraenkungen}

- **profilePattern muss eindeutig sein:** Wenn derselbe Key-Name in mehreren Sektionen
  vorkommt (z.B. `apiKey`), muss der Pattern den Sektions-Kontext einschließen.
  Beispiel: `(treasuremaps\.apiKey\s*=\s*")[^"]*"` statt `(apiKey\s*=\s*")[^"]*"`.

- **Bool-Felder in profile.local.nix:** Nur `true`/`false` — keine anderen Werte.
  Das Portal akzeptiert nur `"true"` oder `"false"` als Wert für `profileType = "bool"`.

- **Rebuild-Pflicht bei domain.base/nixSubdomain:** Diese Felder ändern Caddy vHosts
  und ACME-Domains, die bei Build-Zeit eingebaut werden. Der 3-Minuten-Timer sorgt
  für den nötigen Rebuild.

- **Phase 2 (Stufe 9, TPM):** Wenn `my.creds.enable = true` mit TPM aktiv ist,
  schreibt systemd-creds encrypt mit TPM-Binding. Das Portal läuft als root, hat
  Zugriff auf den host-key — bleibt bis Phase 2 so. Siehe ADR-2024.

## Siehe auch {#siehe-auch}

- [ADR-1034 — secrets-portal Architektur](../adr/1034-secrets-portal-architecture.md)
- [ADR-2024 — systemd-creds + TPM2](../adr/2024-systemd-creds-tpm.md)
- [GUIDE-security-secrets](GUIDE-security-secrets.md)
