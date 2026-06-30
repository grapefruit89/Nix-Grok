---
meta:
  role: doc
  purpose: Caddy Security-Härtung II — Server-Header entfernen, COOP, Scanner-Blocking via abort
  status: accepted
  date: 2026-06-29
  betrifft:
    - lib/caddy-snippets.nix
  docs:
    - docs/adr/README.md
    - docs/adr/014-caddy-security-headers-trusted-proxies.md
    - docs/adr/017-caddy-health-checks-error-fallback.md
    - docs/adr/018-caddy-dual-log-dsgvo.md
  tags:
    - adr
    - caddy
    - sicherheit
    - headers
    - coop
    - scanner
---

# ADR 016 — Caddy Security-Härtung II: Server-Header, COOP, Scanner-Blocking {#adr-016}

## Status {#status}

`accepted` — live auf q958 nach Dry-Build 2026-06-29

## Kontext {#kontext}

Chat-Transcript-Analyse (`deepseek/homelab_server/`) ergab drei weitere fehlende Härtungen in `caddy-snippets.nix`, die in der ersten Caddy-Härtungsrunde ([ADR-014](014-caddy-security-headers-trusted-proxies.md)) übersehen wurden.

### Problem 1: Server-Header gibt Caddy-Version preis {#problem-server-header}

Caddy sendet standardmäßig `Server: Caddy` — gibt Angreifern Web-Server-Typ und ggf. Versionsnummer.

Fix: `header -Server` entfernt den Header komplett.

### Problem 2: Cross-Origin-Opener-Policy fehlte {#problem-coop}

COOP (`Cross-Origin-Opener-Policy: same-origin`) isoliert das Browser-Fenster von fremden Origins:
- Verhindert Zugriff via `window.opener` auf das übergeordnete Fenster
- Notwendig für `SharedArrayBuffer` und `Atomics` in sicheren Kontexten
- Ergänzt `X-Frame-Options` ([ADR-014](014-caddy-security-headers-trusted-proxies.md#snippets)) auf anderer Angriffsfläche

### Problem 3: Keine Scanner-Blockierung {#problem-scanner}

Automatisierte Scanner (Shodan, Censys, Masscan, ZGrab, Nuclei) hinterlassen erkennbare `User-Agent`-Header. Ohne Blockierung erscheinen Scan-Requests in Logs und CrowdSec-Analysen als normaler Traffic.

## Entscheidung {#entscheidung}

Alle drei Änderungen in `lib/caddy-snippets.nix`:

```caddyfile
(security_headers) {
  header {
    ...
    Cross-Origin-Opener-Policy "same-origin"   # neu — Fenster-Isolation
    -Server                                     # neu — Versions-Fingerprinting verhindern
  }
}

(block_scanners) {                              # neu — Scanner sofort trennen
  @scanners header User-Agent *shodan* *masscan* *zgrab* *nmap* *python-requests* *censys* *nuclei*
  abort @scanners
}
```

### Verwendung von `block_scanners` {#block-scanners-usage}

Das Snippet muss in jedem vHost explizit eingebunden werden:

```caddyfile
example.com {
  import block_scanners
  import security_headers
  ...
}
```

Nicht global empfohlen — `python-requests` UA-Block kann legitime interne Skripte treffen.

## Konsequenzen {#konsequenzen}

- **Positiv:** Caddy-Version nicht mehr via `Server`-Header erkennbar
- **Positiv:** Browser-Fenster gegen Opener-basierte Angriffe geschützt
- **Positiv:** Shodan/Censys-Scans landen nicht mehr in CrowdSec-Logs als Noise
- **Achtung:** `python-requests` UA-Block kann legitime interne Skripte treffen

## Alternativen verworfen {#alternativen}

- **`respond 403` statt `abort`:** Sendet HTTP-Response → gibt Server-Typ preis. `abort` ist "stiller" — kein Fingerprinting durch Response. Abgelehnt.
- **fail2ban/CrowdSec für Scanner:** Reagiert erst *nach* dem Request. `abort` verhindert den Request auf Caddy-Ebene sofort. Abgelehnt für Scanner.

## Siehe auch {#siehe-auch}

- [ADR-014 — Caddy Security-Härtung I](014-caddy-security-headers-trusted-proxies.md) — erste Härtungsrunde (Headers + trusted_proxies)
- [ADR-017 — Caddy Health Checks](017-caddy-health-checks-error-fallback.md) — 503-Fallback für ausgefallene Dienste
- [ADR-018 — Caddy Dual-Log DSGVO](018-caddy-dual-log-dsgvo.md) — IP-Anonymisierung in Caddy-Logs
