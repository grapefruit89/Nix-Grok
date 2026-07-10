---
meta:
  role: doc
  purpose: internal Zone — Umbenennung admin-hangar + SSO-Overlay
  status: accepted
  date: 2026-07-08
  tags:
    - caddy
    - zones
    - security
    - sso
    - ingress
  docs:
    - lib/caddy-ingress.nix
    - lib/services-spec.nix
    - docs/adr/1031-caddy-zones-konzept.md
    - docs/adr/1025-pocket-id-oidc-provider.md
---

# ADR-1032: internal Zone — Umbenennung admin-hangar + SSO-Overlay

**Status:** accepted  
**Datum:** 2026-07-08  
**Betrifft:** lib/services-spec.nix, lib/caddy-ingress.nix

## Kontext

Die Zone `admin-hangar` war rein IP-basiert gesichert (`private_admin` Snippet → 403 für WAN-IPs).
Das reichte als erste Schutzschicht, aber es fehlte eine zweite:

1. **Kein Credential-Schutz:** Jeder im LAN oder per Netbird verbundene Client konnte Admin-Dienste
   ohne Authentifizierung aufrufen. Das widerspricht dem Zero-Trust-Prinzip.
2. **Inkonsistenter Name:** `admin-hangar` war ein interner Codename ohne klare semantische Bedeutung.
   `internal` beschreibt den Charakter der Zone präziser (LAN/VPN-intern, nicht öffentlich).

Pocket-ID (OIDC, ADR-1025) und oauth2-proxy waren bereits aktiv. Die technischen Voraussetzungen
für SSO auf der `internal`-Zone waren also vollständig vorhanden.

## Entscheidung

1. **Umbenennung:** `admin-hangar` → `internal` in `lib/services-spec.nix` (zones-Enum + alle
   Service-Einträge) und `lib/caddy-ingress.nix` (zone-String-Vergleich).

2. **SSO-Overlay:** Die `internal`-Zone erhält zusätzlich zu `private_admin` die Snippets
   `sso_auth` + `sso_redirect`. Snippet-Reihenfolge in `genZoneVhost`:
   ```
   import private_admin    ← IP-Sperre zuerst (WAN-Clients kommen nicht durch)
   import sso_auth         ← Pocket-ID Session-Check für LAN/VPN-Clients
   import sso_redirect     ← 401 → Login-Redirect
   import security_headers
   import upstream_errors
   ```

3. **Services mit eigenen Generatoren sind ausgenommen:** `genVaultwardenVhost`,
   `genSecurityOnlyVhost` etc. lesen die Zone nicht — sie bleiben unverändert.
   Vaultwarden hat eigenes Auth-System und bekommt kein SSO-Overlay, obwohl es
   in der `internal`-Zone ist.

## Begründung

- **Defense in depth:** IP-Sperre + SSO = zwei unabhängige Schichten. Auch ein Gerät im LAN
  muss sich authentifizieren.
- **Konsistenz:** `internal` und `family-pocketid` nutzen jetzt beide Pocket-ID als Auth-Layer.
  Der Unterschied ist nur noch: WAN-Erreichbarkeit ja/nein.
- **Kein operativer Overhead:** Pocket-ID ist bereits aktiv. Session-Cookies gelten für alle
  Subdomains (`.DOMAIN`) — einmal einloggen, alle Dienste verfügbar.

## Konsequenzen

- Admin-Dienste (Grafana, Gatus, Scrutiny, SABnzbd, Sonarr/Radarr/...) benötigen nun
  einen aktiven Pocket-ID-Login. Das ist gewünscht.
- Beim ersten Aufruf nach dem Switch: Login-Redirect zu `auth.DOMAIN`. Nach Login: normale
  Nutzung wie bisher.
- Der Sonderfall `genVaultwardenVhost` sollte dokumentiert bleiben — er überschreibt die
  Zone-basierte Logik explizit.
