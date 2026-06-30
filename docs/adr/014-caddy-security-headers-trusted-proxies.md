---
meta:
  role: doc
  purpose: Caddy Security-Härtung — Security Headers + trusted_proxies (KB-Analyse 2026-06-29)
  status: accepted
  date: 2026-06-29
  betrifft:
    - lib/caddy-snippets.nix
    - modules/10-network/11-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/016-caddy-security-headers-coop-scanners.md
    - docs/adr/017-caddy-health-checks-error-fallback.md
    - docs/adr/018-caddy-dual-log-dsgvo.md
  tags:
    - adr
    - caddy
    - sicherheit
    - headers
    - trusted-proxies
---

# ADR 014 — Caddy Security-Härtung: Headers + trusted_proxies {#adr-014}

## Status {#status}

`accepted` — live auf q958 nach Dry-Build 2026-06-29

## Kontext {#kontext}

Chat-Transcript-Analyse (USB-Stick, claude/homelab_server/) ergab drei Probleme in `caddy-snippets.nix`:

1. **`X-XSS-Protection "1; mode=block"`** — veraltet und gefährlich:
   - Der XSS Auditor wurde in Chrome/Edge/Firefox komplett entfernt.
   - `mode=block` kann als Side-Channel-Angriff ausgenutzt werden.
   - Moderner Standard ist `"0"`.

2. **`X-Frame-Options "DENY"`** — zu restriktiv:
   - Blockiert auch *eigene* iframes (z. B. Jellyfin-Player, Home-Assistant-Dashboards).
   - `"SAMEORIGIN"` ist der korrekte Wert.

3. **`Permissions-Policy` fehlte komplett**:
   - Browser können ohne diesen Header Geolocation, Mikrofon, Kamera für jede Seite freischalten.

4. **`trusted_proxies` fehlte im `globalConfig`**:
   - Ohne `servers { trusted_proxies static private_ranges }` ignoriert Caddy `X-Forwarded-For`.
   - IP-basierte Checks (`@external`, CrowdSec-Bouncer, Geoblock) sehen immer die Proxy-IP.

## Entscheidung {#entscheidung}

### `lib/caddy-snippets.nix` {#snippets}

```
X-XSS-Protection "0"             # war: "1; mode=block"
X-Frame-Options "SAMEORIGIN"     # war: "DENY"
Permissions-Policy "geolocation=(), microphone=(), camera=()"  # neu
```

### `modules/10-network/11-network.nix` {#network-config}

```nix
services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
  servers {
    trusted_proxies static private_ranges
  }
'';
```

## Konsequenzen {#konsequenzen}

- **Positiv:** Security-Headers entsprechen OWASP-Empfehlungen 2024+.
- **Positiv:** Caddy kennt echte Client-IPs auch hinter künftigen Proxies.
- **Neutral:** `trusted_proxies private_ranges` vertraut nur RFC-1918-Adressen.
- **Kein Breaking Change:** `SAMEORIGIN` ist kompatibler als `DENY`.

## Alternativen verworfen {#alternativen}

- **Caddy Geoblock (Maxmind):** Abgelehnt — Geoblock läuft bereits auf Kernel-Ebene via nftables `geoip_blocked` Set ([ADR-008](008-nftables-l4-hardening.md)). Caddy soll thin bleiben.
- **fail2ban/CrowdSec für Headers:** Nicht zuständig — Headers sind Caddy-Aufgabe, Blocking ist nftables-Aufgabe.

## Siehe auch {#siehe-auch}

- [ADR-016 — Caddy Security-Härtung II](016-caddy-security-headers-coop-scanners.md) — Server-Header, COOP, Scanner-Blocking (Fortsetzung)
- [ADR-017 — Caddy Health Checks](017-caddy-health-checks-error-fallback.md) — 503-Fallback für ausgefallene Dienste
- [ADR-018 — Caddy Dual-Log DSGVO](018-caddy-dual-log-dsgvo.md) — IP-Anonymisierung in Caddy-Logs
- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — Geoblock auf Kernel-Ebene (komplementär)
