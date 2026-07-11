# Audit: modules/20-security
Datum: 2026-07-11
Auditor: Grok (Drift-Prevention — Re-Audit nach P1/P2/P3)

## Bewertungskriterien

| Kriterium | Anforderung |
|-----------|-------------|
| Timer ≠ Cron | Kein `services.cron` |
| Kein POSIX-Legacy | Kein Runtime-Fetch wo Store/Nix reicht |
| Deklarativ-first | NixOS-Optionen, tmpfiles, Assertions |
| SSoT / fail-closed | Ports in Registry, Secrets über systemd-creds |
| Policy-Alignment | `forbidden-tech.nix`: kein cron, kein iptables, kein sops |

## Übersicht

11 Module (ADR-011 Isomorphie: `2015-firewall`, `2020-security`, `2021-sovereign-unlock`, `2022-fail2ban`, `2023-acme`, `2025-kernel-policy`, `2026-kernel-hardening`, `2027-hardened-core`, `2028-oauth2-proxy`, `2029-secrets-portal`).

**Gesamturteil:** Deklarative Kernmodule stark. GeoIP DE/AT/LT Store-basiert. **Secrets-Migration 20-security abgeschlossen:** oauth2-proxy + ACME nur noch `LoadCredentialEncrypted` (kein `/var/lib/secrets/`-Fallback). Verbleibendes POSIX: initrd/LUKS (unvermeidbar), Fail2ban-Daemon (upstream).

---

## Status vs. Audit 2026-07-10

| Finding (alt) | Status 2026-07-11 |
|---------------|-------------------|
| GeoIP DE Runtime-curl | ✓ **Behoben** (vorher) — `geoip-de.zone` + `nftables-geoip-de` |
| GeoIP AT/LT Runtime-curl | ✓ **Behoben** — `geoip-at.zone`, `geoip-lt.zone` + Store-Services |
| Dropbear ExecStartPre Shell | ✓ **Behoben** — tmpfiles-Symlinks in `2020-security.nix` |
| Ports 2222/4180 hardcodiert | ✓ **Behoben** — `my.ports.dropbear`, `my.ports.oauth2-proxy` |
| oauth2 `/var/lib/secrets/` | ✓ **Behoben** — `clientId` in Nix + `client-secret`/`cookie-secret` credstore |
| ACME `/var/lib/secrets/` | ✓ **Behoben** — `CF_DNS_API_TOKEN_FILE` credstore (lego `_FILE`-Suffix) |
| secrets-portal nicht enabled | ✓ **Behoben** — `default.nix` Stufe 8+ |
| 21-sovereign-unlock QR-Shell | ⚠ **Offen (niedrig)** — initrd awk/grep teils unvermeidbar |
| fail2ban iptables-Enum | ⚠ **Offen (niedrig)** — Policy-Härte optional |

---

## Legacy/POSIX-Inventar

| Datei | Shell/POSIX | Schwere |
|-------|-------------|---------|
| 2015-firewall.nix | — (Store nft) | — |
| 2020-security.nix | — (tmpfiles) | — |
| 2021-sovereign-unlock.nix | initrd + QR Shell | Mittel* |
| 2022-fail2ban.nix | Fail2ban upstream | Niedrig |
| 2023-acme.nix | — | — |
| 2028-oauth2-proxy.nix | — | — |
| 2029-secrets-portal.nix | — (Go) | — |

\* initrd bash akzeptabel

---

## Datei-Audits (Kurz)

### 2015-firewall.nix — ✓
nftables aus `lib/nftables-rules.nix`. GeoIP: DE flush+load, AT/LT `add element` aus vendorten `.zone`-Files. Assertion FIREWALL-004 für unbekannte Länder. `geoipAutoUpdate` entfernt (kein Runtime-Fetch mehr).

### 2020-security.nix — ✓
SSH Zero-Trust + Dropbear via tmpfiles, Port aus `my.ports.dropbear`.

### 2021-sovereign-unlock.nix — ⚠
LUKS/TPM deklarativ; QR-Fallback noch Runtime-IP-Erkennung — LAN-IP aus Config möglich.

### 2023-acme.nix — ✓
DNS-01 Cloudflare. Pflicht `my.creds.enable`. `LoadCredentialEncrypted=cloudflare_acme_env` — kein Legacy-Pfad.

### 2028-oauth2-proxy.nix — ✓
Forward-Auth, Port aus Registry. Pflicht `my.creds.enable`. env + cookie-secret nur credstore.

### 2029-secrets-portal.nix — ✓
Aktiv auf q958; 10 Secrets inkl. oauth2 + ACME.

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| Cron-Verbot | ✓ | Kein cron |
| GeoIP | ✓ | DE+AT+LT Store, kein ipdeny-Timer |
| Secrets (20-security) | ✓ | Kein `/var/lib/secrets/` in Modulen; live: oauth2 + acme active |
| Port-SSoT | ✓ | dropbear, oauth2 in `08-ports.nix` |
| Shell-Legacy | ⚠ | sovereign-unlock QR; CrowdSec in 40-observability |

## Priorisierte Empfehlungen

1. **Sovereign-unlock QR** — statische LAN-IP aus `my.configs.server.lanIP` (niedrig)
2. **fail2ban banaction-Enum** — `iptables-*` entfernen (Policy-Härte)
3. **gateway.nix cloudflare_api_token** — Pattern-B credstore-Migration (10-network, ROADMAP Schritt 4)
4. **secrets.nix Provision** — Gesamt-Repo (~20 Module außerhalb 20-security) noch auf `/var/lib/secrets/`