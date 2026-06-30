---
meta:
  role: doc
  purpose: Caddy Dual-Log — DSGVO-Datei mit IP-Anonymisierung + journald für CrowdSec
  status: accepted
  date: 2026-06-29
  error_pattern: "strconv\\.Atoi.*invalid syntax|ip_mask.*parsing error|error parsing.*ip_mask"
  quick_fix: "ip_mask 24 statt /24 in Caddyfile (kein Slash!)"
  services: [caddy]
  betrifft:
    - modules/10-network/11-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/014-caddy-security-headers-trusted-proxies.md
    - docs/adr/016-caddy-security-headers-coop-scanners.md
    - docs/adr/017-caddy-health-checks-error-fallback.md
    - docs/RUNBOOK.md
  tags:
    - adr
    - caddy
    - dsgvo
    - logging
    - crowdsec
    - ip-anonymisierung
---

# ADR 018 — Caddy Dual-Log: DSGVO-Datei + journald für CrowdSec {#adr-018}

## Status {#status}

`accepted` — live auf q958, 2026-06-29

## Kontext {#kontext}

Caddy schreibt HTTP-Access-Logs standardmäßig über den Default-Logger auf `stdout`, der
von systemd als Journal-Eintrag erfasst wird. CrowdSec liest diese Einträge über
`journalctl --unit=caddy.service` (volle IPs — für Anomalie-Erkennung erforderlich).

Für DSGVO-Konformität (Art. 5 Abs. 1 lit. e DSGVO / Datensparsamkeit) dürfen
IP-Adressen in persistenten Logs nicht vollständig gespeichert werden. Journald-Logs
sind ephemer und rotieren automatisch — sie fallen unter den Sicherheitszweck. Eine
separate Datei für Audit/Compliance-Zwecke muss aber IP-anonymisiert sein.

Die Caddy-Härtungsrunde ([ADR-014](014-caddy-security-headers-trusted-proxies.md)) fügte
`trusted_proxies` hinzu — dadurch wird `client_ip` korrekt befüllt und muss ebenfalls
maskiert werden.

## Entscheidung {#entscheidung}

Caddy erhält **einen zweiten globalen Log-Handler** (`dsgvo_access`) zusätzlich zum
unveränderten Default-Logger.

### Architektur {#architektur}

```
HTTP-Request
    │
    ├─► default-Logger (stdout → journald → CrowdSec)
    │       format: JSON, volle IP
    │       retention: journald-Policy (~2 Wochen rollierend)
    │
    └─► dsgvo_access-Logger (Datei /var/log/caddy/dsgvo.json)
            format: JSON mit ip_mask 24 (IPv4) / 48 (IPv6)
            retention: 14 Dateien × 100 MB, max. 30 Tage (720h)
```

### Umsetzung {#umsetzung}

In `services.caddy.globalConfig` (→ Caddyfile Global Options Block):

```caddyfile
log dsgvo_access {
  include http.log.access
  output file /var/log/caddy/dsgvo.json {
    roll_size 100mb
    roll_keep 14
    roll_keep_for 720h
  }
  format filter {
    wrap json
    fields {
      request>remote_ip ip_mask { ipv4 24; ipv6 48 }
      request>client_ip ip_mask { ipv4 24; ipv6 48 }
    }
  }
  level INFO
}
```

**Wichtig:** `ip_mask 24` ohne Slash — `ip_mask /24` verursacht `strconv.Atoi`-Fehler und Endlos-Restart-Loop!

### DSGVO-Felder maskiert {#dsgvo-felder}

| Feld | Vorher | Nachher |
|------|--------|---------|
| `request.remote_ip` | `93.184.216.34` | `93.184.216.0` |
| `request.client_ip` | `93.184.216.34` | `93.184.216.0` |
| IPv6 `request.remote_ip` | `2001:db8::1` | `2001:db8::` (/48) |

`client_ip` ist Caddy ≥ 2.7-Standardfeld (nach X-Forwarded-For-Auflösung via [ADR-014](014-caddy-security-headers-trusted-proxies.md#network-config)) und muss ebenfalls maskiert werden.

## Diagnose {#diagnose}

**Symptom:** Caddy startet nicht oder crashed in Schleife nach Änderung an der Log-Konfiguration.

```bash
journalctl -u caddy -n 30 --no-pager | grep -iE "error|fail|strconv|ip_mask"

# Typischer Fehler:
# Error: adapting config using caddyfile: error parsing ip_mask /24: strconv.Atoi: ...
```

**Bekanntes Gotcha:** `ip_mask /24` (mit Slash) → Syntaxfehler → Caddy-Crash-Loop.

## Fix {#fix}

```bash
# Syntaxfehler: /24 → 24 (kein Slash bei ip_mask!)
grep -rn "ip_mask" /etc/nixos/modules/

# Fix in modules/10-network/11-network.nix:
#   ip_mask { ipv4 /24 → ip_mask { ipv4 24
#   ip_mask { ipv6 /48 → ip_mask { ipv6 48

sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
# in tmux: sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure
```

Vollständige Fehlerdetails: [RUNBOOK — Caddy](../RUNBOOK.md#caddy-ip-mask)

## Alternativen verworfen {#alternativen}

| Alternative | Verworfen weil |
|-------------|----------------|
| Journald-Export via systemd-Einheit | Komplexität, kein Caddy-nativer Ansatz |
| `log <name>` per vHost | Würde Default-Logger deaktivieren → CrowdSec bricht |
| CrowdSec auf Datei umstellen | Änderung an funktionierender Sicherheitskomponente, unnötig |
| Einziger Logger mit Masking | CrowdSec benötigt volle IPs für Anomalie-Erkennung |

## Konsequenzen {#konsequenzen}

- **Positiv:** CrowdSec unverändert (journald, volle IPs)
- **Positiv:** DSGVO-Compliance für persistente Access-Logs
- **Positiv:** Kein einziger vHost muss angepasst werden
- **Positiv:** Caddy-native Rotation (kein logrotate nötig)
- **Neutral:** ~1.4 GB maximaler Log-Verbrauch unter `/var/log/caddy/`
- **Zu beachten:** Bei Upgrade auf Caddy < 2.7 fällt `client_ip`-Feld weg (unkritisch, Masking läuft dann ins Leere)

## Siehe auch {#siehe-auch}

- [ADR-014 — Caddy Security-Härtung I](014-caddy-security-headers-trusted-proxies.md) — `trusted_proxies` macht `client_ip` relevant
- [ADR-016 — Caddy Security-Härtung II](016-caddy-security-headers-coop-scanners.md) — Scanner-Blocking (komplementär)
- [ADR-017 — Caddy Health Checks](017-caddy-health-checks-error-fallback.md) — 503-Fallback
- [RUNBOOK — Caddy ip_mask](../RUNBOOK.md#caddy-ip-mask) — Quick-Fix bei ip_mask Syntaxfehler
