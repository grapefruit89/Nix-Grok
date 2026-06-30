---
meta:
  role: doc
  purpose: Caddy Health Checks und 503-Fallback — upstream_errors Snippet für alle vHosts
  status: accepted
  date: 2026-06-29
  error_pattern: "bad gateway|upstream.*unhealthy|connection refused.*upstream|502.*caddy"
  quick_fix: "systemctl status <dienst>; curl -I https://<vhost>.domain.tld"
  services: [caddy]
  betrifft:
    - lib/caddy-snippets.nix
    - lib/caddy-ingress.nix
  docs:
    - docs/adr/README.md
    - docs/adr/014-caddy-security-headers-trusted-proxies.md
    - docs/adr/016-caddy-security-headers-coop-scanners.md
    - docs/adr/018-caddy-dual-log-dsgvo.md
  tags:
    - adr
    - caddy
    - health-checks
    - 503
    - stabilität
---

# ADR 017 — Caddy Health Checks und 503-Fallback {#adr-017}

## Status {#status}

`accepted` — live auf q958 nach Dry-Build 2026-06-29

## Kontext {#kontext}

Chat-Transcript-Analyse ergab: Wenn ein proxiierter Dienst ausfällt, sendet Caddy standardmäßig eine rohe `502 Bad Gateway`-Seite zurück.

### Problem 1: Keine 503-Fallback-Seite {#problem-503}

**RFC-Semantik:**
- `502` = Bad Gateway (Caddy konnte Upstream nicht erreichen)
- `503` = Service Unavailable (bewusst: "Service gerade down")

`503` kommuniziert für Endnutzer klarer "Service momentan nicht erreichbar".

### Problem 2: Aktive Upstream-Health-Checks nicht praktikabel {#problem-health-checks}

Caddy hat passive Health Checks (erkennt fehlgeschlagene Responses automatisch). Aktive Health Checks (`health_uri`) erfordern pro Service einen bekannten Endpunkt — die Dienste haben unterschiedliche Endpunkte. Kein einheitliches Muster möglich.

**Passiver Health Check (Standard-Caddy):** Caddy markiert Upstreams automatisch als unhealthy nach fehlgeschlagenen Requests. Ausreichend für 1-Personen-Homelab.

## Entscheidung {#entscheidung}

### Lösung: `(upstream_errors)` Snippet {#upstream-errors}

In `lib/caddy-snippets.nix`:

```caddyfile
(upstream_errors) {
  handle_errors 502 503 {
    respond "Service momentan nicht verfügbar" 503
  }
}
```

Eingebunden in **alle** vHost-Generatoren in `lib/caddy-ingress.nix`:
- `genAuthVhost` (Pocket-ID)
- `genJellyfinVhost`, `genNavidromeVhost`, `genVaultwardenVhost`
- `genSecurityOnlyVhost` (Homepage, AMP, Home-Assistant, Zigbee-Stack)
- `genZoneVhost` (alle Zone-basierten Dienste)

### Warum `handle_errors` statt `respond @unhealthy` {#handle-errors-begruendung}

`handle_errors` ist die standardisierte Caddy-Direktive für Fehlerbehandlung — greift auf alle 502/503 aus dem Upstream unabhängig vom Handler.

## Diagnose {#diagnose}

**Symptom:** Nutzer sieht "Service momentan nicht verfügbar" (503) oder rohe 502-Seite.

```bash
# Betroffenen Dienst identifizieren
systemctl list-units --state=failed

# Upstream-Status prüfen (Beispiel Sonarr)
systemctl status sonarr --no-pager
curl -s http://localhost:5003/ping

# Caddy-Logs auf Upstream-Fehler
journalctl -u caddy -n 30 --no-pager | grep -iE "upstream|502|503|refused"
```

## Fix {#fix}

```bash
# 1. Betroffenen Dienst neu starten
sudo systemctl restart <dienst>

# 2. Verifikation: vHost antwortet wieder
curl -I https://<vhost>.<domain>
# Erwartete Antwort: HTTP/2 200 (oder 301/302 für Login)
```

## Konsequenzen {#konsequenzen}

**Positiv:**
- Nutzer sehen klare "Service momentan nicht verfügbar"-Meldung statt rohem `502 Bad Gateway`
- Implementierung minimal-invasiv (ein Snippet, `import upstream_errors` pro vHost)
- Kein Overhead durch aktive Health-Check-Requests

**Negativ / Einschränkungen:**
- Keine proaktive Erkennung vor dem ersten Request
- Fehlermeldung ist plain text, kein gestaltetes HTML (bewusst einfach gehalten)

## Verifikation {#verifikation}

```bash
# Einen Dienst temporär stoppen:
sudo systemctl stop sonarr
# Request an Sonarr-vHost:
curl -I https://sonarr.example.com
# Erwartete Antwort: HTTP/2 503 + Body "Service momentan nicht verfügbar"
sudo systemctl start sonarr
```

## Alternativen verworfen {#alternativen}

- **Aktive `health_uri` pro Dienst** — keine einheitlichen Health-Endpunkte, zusätzliche Netzwerklast. Nicht praktikabel.
- **Gestaltete 503-HTML-Seite** — Komplexität ohne Mehrwert für 1-Personen-Homelab. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-014 — Caddy Security-Härtung I](014-caddy-security-headers-trusted-proxies.md) — Headers + trusted_proxies
- [ADR-016 — Caddy Security-Härtung II](016-caddy-security-headers-coop-scanners.md) — Scanner-Blocking
- [ADR-018 — Caddy Dual-Log DSGVO](018-caddy-dual-log-dsgvo.md) — IP-Anonymisierung
- [RUNBOOK — Caddy](../RUNBOOK.md#caddy) — Caddy-spezifische Diagnose-Befehle
