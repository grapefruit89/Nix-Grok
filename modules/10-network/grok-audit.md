# Audit: modules/10-network
Datum: 2026-07-10
Auditor: Grok

## Übersicht

`modules/10-network/` ist die Netzwerk- und Ingress-Schicht: Host-DNS (DoT via resolved), LAN-DNS (Blocky), Caddy-Basisconfig + Spec-Ingress, Datenbanken (Valkey/PostgreSQL), Gateway (DDNS), VPN (Netbird/Privado) und Identity (Pocket-ID). Die Architektur folgt dem bewussten Split: **Host resolved → DoT direkt**, **LAN-Clients → Blocky → DoT** — kein Chicken-Egg.

Stärken: strukturierte DNS/IPv6-Assertions (ADR-1001/1002), Caddy `trusted_proxies` korrekt einzeilig, Spec-basierter Ingress als SSoT, Privado Split-Tunnel über UID-Registry. Schwächen: fehlende Meta-Header in mehreren Dateien, hardcodierte Ports/Magic Numbers, Valkey-Socket-Drift zwischen `services-spec` und `unix-sockets`, und Caddy-Config verteilt über drei Module (10-network + 20-security).

---

## Datei-Audits

### default.nix
**Zweck:** Aggregiert alle 10-network-Untermodule in logischer Reihenfolge (Basis → DNS → Gateway → Ingress → DB → VPN → IdP).

**Bewertung:** ✓

**Findings:**
- Import-Reihenfolge sinnvoll: `11-network` (Host-DNS + Caddy-Global) vor `12-blocky`, `14-ingress` nach Spec-Voraussetzungen aus 00-core.
- Header-Kommentar vollständig und korrekt.
- Kein README im Ordner — im Gegensatz zu 00-core keine lokale Doku.

**Abhängigkeiten:** `./11`–`./17`-Module.

**Empfehlung:** keep as-is (optional: README ergänzen)

---

### 11-network.nix
**Zweck:** Kern-Netzwerkmodul — IPv6-Per-Interface-Disable, Host-DNS (resolved DoT strict), DNS/IPv6-Assertions, Caddy-Globalconfig (trusted_proxies, DSGVO-Logger, Snippets), Host-Split-Horizon via `extraHosts`.

**Bewertung:** ✓

**Findings:**
- **DoT fail-closed:** `DNSOverTLS = "yes"`, `FallbackDNS = ""`, `nameservers = []`, `resolvconf.enable = false` — vorbildlich, Assertions DNS-001..004 mit `lib/assertions.nix` (code/was/warum/beheben).
- **IPv6:** Per-Interface-sysctl + `enableIPv6 = false` + Assertions IPv6-001/002 — konsistent mit v4-only Homelab (ADR-1002).
- **Caddy trusted_proxies:** Alle CF-Ranges in **einer Zeile** — Projektregel eingehalten.
- **DSGVO-Logger:** IP-Maskierung /24 (v4) / /48 (v6) — Privacy-by-design, auch wenn v6 deaktiviert.
- **extraHosts:** Generiert LAN-IP → alle Spec-Subdomains für Host-seitige Auflösung (Host nutzt resolved, nicht Blocky) — korrektes Split-Horizon-Muster.
- **Hardcodiert:** `lanCidr = "192.168.0.0/16"` — passt für q958 (192.168.2.73), aber nicht aus `profile.nix` abgeleitet; bei anderem LAN-CIDR müsste man hier editieren.
- **Hardcodiert:** `oauth2proxyPort = 4180` — oauth2-proxy-Standard, aber nicht in `my.ports` (Konvention aus 00-core-Audit).
- **Cross-Layer:** Caddy-Snippets aus `lib/caddy-snippets.nix`; oauth2-proxy-Modul lebt in `20-security/28-oauth2-proxy.nix`, Snippet-Port hier verdrahtet — funktional ok, aber Ingress-SSoT ist aufgeteilt.
- Kein YAML-Meta-Header (nur Zeilenkommentar am Dateianfang) — inkonsistent mit `12-blocky.nix`, `13-gateway.nix`, `14-ingress.nix`.

**Abhängigkeiten:** `lib/assertions.nix`, `lib/caddy-snippets.nix`, `config.my.configs.network.*`, `config.my.services.spec`, `config.services.caddy`, `config.my.services.oauth2-proxy`, `config.my.services.pocket-id`

**Empfehlung:** minor cleanup — `lanCidr` aus Profil ableiten; oauth2-Port in `my.ports` registrieren; Meta-Header ergänzen

---

### 12-blocky.nix
**Zweck:** Blocky DNS für LAN-Clients — Ad-Blocking, Split-Horizon, DoT-Upstreams, Prometheus-Metriken.

**Bewertung:** ⚠

**Findings:**
- DNS nur auf `${lanIP}:53` — nicht auf 0.0.0.0/WAN; `network.nix` öffnet Port 53 nur auf LAN-Interface vor nftables-Stufe 8. Bewusstes Design.
- Upstreams aus `my.configs.network.dnsBootstrap` → `tcp-tls:IP:853` — SSoT mit resolved, diversifiziert (8 Resolver in `profile.nix`).
- `customDNS.mapping` mit Apex-Domain + `filterUnmappedTypes = false` — laut Migrations-Design deckt das `*.domain` ab (funktional identisch zu Technitium-Wildcard).
- **Nicht vollständig deklarativ:** `whiteLists.ads = [ "/home/moritz/blocky-allowlist.txt" ]` — benutzerpfad, Inhalt manuell gepflegt. `tmpfiles` erstellt leere Datei, `ProtectHome = read-only` erlaubt Lesen — pragmatischer Dev-Kompromiss.
- OOMScoreAdjust -300 — konsistent mit OOM-Policy.
- Keine Build-Assertion dass Blocky aktiv → LAN-DNS = 127.0.0.1 (liegt in `machines/q958/access.nix` — ok, aber maschinenspezifisch).

**Abhängigkeiten:** `config.my.ports.blocky`, `config.my.configs.network.dnsBootstrap`, `config.my.configs.server.lanIP`, `config.my.configs.identity.domain`

**Empfehlung:** minor cleanup — Allowlist-Pfad konfigurierbar machen (`my.services.blocky.allowlistFile`); oder als bewussten Dev-Override dokumentieren

---

### 13-gateway.nix
**Zweck:** DDNS-Updater (Cloudflare A-Record) + optionaler DNS-Guard (Wildcard-Konflikt-Check).

**Bewertung:** ✓

**Findings:**
- `my.configs.ddns` (zone/record) als Options-SSoT — Werte aus `profile.nix` via `default.nix`.
- DDNS hängt an `q958-secrets-provision` — korrekte Secret-Abhängigkeit.
- `service-factory.systemdHardening` für ddns-updater — gute Wiederverwendung.
- `impermanence.extraPaths` für `/var/lib/ddns-updater` — Stufe-9-ready.
- **dns-guard:** Soft-Check — Warnung bei Wildcard-Konflikt, `exit 0` (bricht nicht ab). Analog zu creds-Check in 00-core.
- Option `dns-guard` beschreibt „ohne SOPS" — korrekte Policy, etwas veraltete Terminologie.
- `dns-guard` Timer ohne explizites `unit =` — NixOS-Konvention (gleicher Name) greift.

**Abhängigkeiten:** `lib/service-factory.nix`, `config.my.ports.ddns-updater`, `config.my.configs.ddns`, `q958-secrets-provision`

**Empfehlung:** keep as-is

---

### 14-ingress.nix
**Zweck:** Spec-basierter Caddy-Ingress — einzige Quelle für Service-vHosts aus `my.services.spec`. Definiert `my.ingress.fromSpec`.

**Bewertung:** ✓

**Findings:**
- Schlankes Modul — delegiert an `lib/caddy-ingress.nix` + `lib/service-enable.nix`.
- `my.ingress.fromSpec.enable` defaultet auf `services.caddy.enable` — sinnvoll.
- ACME-Host wird gesetzt wenn `my.security.acme.enable` — Verknüpfung mit `20-security/23-acme.nix`.
- Zone-basierte vHost-Generierung (internal/external/streaming) mit SSO, private_admin, Streaming-Spezialfällen (Jellyfin, Navidrome) — gut strukturiert in Lib.
- **Nicht alle vHosts hier:** `oauth.${domain}` kommt aus `20-security/28-oauth2-proxy.nix` — bewusste Ausnahme (Auth-Endpunkt, nicht in Spec-Matrix).
- Assertion in `04-services-spec.nix` erzwingt fromSpec wenn Caddy aktiv — Guardrail funktioniert.

**Abhängigkeiten:** `lib/caddy-ingress.nix`, `lib/caddy-helpers.nix`, `lib/service-enable.nix`, `config.my.services.spec`, `config.my.security.acme`

**Empfehlung:** keep as-is

---

### 15-databases.nix
**Zweck:** Valkey (UDS-only) und PostgreSQL (UDS-only, lokal ident-auth).

**Bewertung:** ⚠

**Findings:**
- **Valkey:** `port = 0`, Unix-Socket via `lib/unix-sockets.nix` (`valkey.sock`), `RestrictAddressFamilies = [ AF_UNIX ]` — UDS-first (ADR-1019), vorbildlich.
- **Valkey:** `unixSocketPerm = 666` — permissiv, aber nur UDS; Kommentar erklärt Pocket-ID-Abhängigkeit. Bewusster Tradeoff.
- **PostgreSQL:** `enableTCPIP = false`, `listen_addresses = ""`, ident-only — sicher für Loopback-Nutzung.
- RAM-skalierte Postgres-Settings (`shared_buffers`, `effective_cache_size`) aus `ramGB` — sinnvoll für 32 GB q958.
- `memory.postgres` aus `lib/memory-policy.nix` — OOM-Isolation.
- **Socket-Drift:** `lib/services-spec.nix` nennt Valkey-Socket `/run/redis-valkey/redis.sock`, tatsächlich `/run/redis-valkey/valkey.sock` (unix-sockets.nix + 15-databases). Spec-Eintrag ist loopback (kein Caddy), aber SSoT-Inkonsistenz.
- **Kein Meta-Header** — im Gegensatz zu anderen Modulen.
- PostgreSQL aktuell `enable = false` in rollout — Modul ist trotzdem production-ready für künftige Aktivierung.

**Abhängigkeiten:** `lib/unix-sockets.nix`, `lib/memory-policy.nix`, `config.my.configs.hardware.ramGB`

**Empfehlung:** minor cleanup — Valkey-Socket in `services-spec.nix` korrigieren; Meta-Header ergänzen

---

### 16-vpn.nix
**Zweck:** Netbird Self-Hosted (Management/Signal/Client) + Privado WireGuard Split-Tunnel für Usenet-UIDs.

**Bewertung:** ⚠

**Findings:**
- **Netbird:** `enableNginx = false` — Caddy übernimmt Ingress, kein doppelter Reverse-Proxy. Korrekt.
- **Netbird OIDC:** `oidcConfigEndpoint = "http://127.0.0.1:1001/..."` — hardcodiert statt `config.my.ports.pocket-id`. Bricht bei Port-Änderung.
- **Netbird:** Metrics-Ports 6060/6061/6062 hardcodiert — intern, akzeptabel.
- **Netbird:** Firewall-Ports (3478, 10000, 33073) hardcodiert — nicht in `my.ports`.
- **Privado Split-Tunnel:** UID-basierte `ip rule` für prowlarr/sabnzbd aus `my.users.registry` — exzellentes ADR-011-Muster, deklarativ.
- `table = "off"` + eigene Routing-Tabelle 51820 — vermeidet resolvconf-Konflikt, gut dokumentiert.
- **ADR-2030-Fix:** `systemd-networkd-wait-online.wantedBy = mkForce []` + Regression-Assertion — verhindert 2min rebuild-block. Vorbildlich.
- **Kein Meta-Header.**

**Abhängigkeiten:** `config.my.users.registry`, `config.my.services.netbird`, `config.my.services.privado-vpn`, `pkgs.iproute2`

**Empfehlung:** minor cleanup — Pocket-ID-Port aus `my.ports` statt 1001; Meta-Header; optional Netbird/Firewall-Ports in Registry

---

### 17-pocket-id.nix
**Zweck:** Pocket-ID OIDC Identity Provider — Passkeys, Session, Proxy-Trust.

**Bewertung:** ✓

**Findings:**
- Port aus `my.ports.pocket-id` (default 1001) — SSoT eingehalten.
- `ip_unprivileged_port_start = 1000` — nötig für Port < 1024 ohne Root.
- `APP_URL`/`RP_ID` auf `auth.${domain}` — konsistent mit dns-map und services-spec.
- `PUBLIC_REGISTRATION = false` — korrekt für Homelab-IdP.
- `TRUST_PROXY = true` — nötig hinter Caddy; passt zu `private_admin`/`trusted_proxies`-Kette.
- `memory.pocketId` + umfangreiche systemd-Hardening — gut.
- Secrets via optionales `secretsFile` — Pfad aus `network.nix`/`profile.nix`.
- `impermanence.extraPaths` für dataDir.
- **Kein Meta-Header.**

**Abhängigkeiten:** `lib/memory-policy.nix`, `config.my.ports.pocket-id`, `config.my.configs.identity.domain`

**Empfehlung:** keep as-is (Meta-Header optional)

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| DNS DoT fail-closed | ✓ | Host resolved strict, Assertions DNS-001..004 |
| Split-Horizon | ✓ | Blocky apex+subdomains, Host extraHosts |
| Caddy trusted_proxies | ✓ | Eine Zeile, CF-Ranges vollständig |
| Ingress SSoT | ⚠ | Spec-Ingress in 14; Global in 11; oauth-vHost in 20-security |
| Port-SSoT | ⚠ | 4180, 1001 (Netbird), 51820, Netbird-FW-Ports nicht in `my.ports` |
| UDS-first | ✓ | Valkey + Postgres socket-only; Socket-Pfad-Drift in Spec |
| Deklarativität | ⚠ | Blocky-Allowlist user-pfad, nicht im Nix-Store |
| VPN Split-Tunnel | ✓ | UID-basiert, Regression-Assertion ADR-2030 |
| Meta-Header | ⚠ | 15, 16, 17, 11 ohne strukturierten Header |

## Priorisierte Empfehlungen

1. **Valkey-Socket in `lib/services-spec.nix` korrigieren** — `redis.sock` → `valkey.sock`
2. **Netbird OIDC-Endpoint** — `127.0.0.1:1001` → `config.my.ports.pocket-id`
3. **`my.ports.oauth2-proxy = 4180`** in `08-ports.nix` + Verdrahtung in 11-network und 28-oauth2-proxy
4. **Meta-Header** für 11, 15, 16, 17 ergänzen (Konsistenz mit Rest des Repos)
5. **Blocky-Allowlist** als Option (`my.services.blocky.allowlistFile`) — Pfad nicht hardcoden
6. **README.md** für 10-network anlegen (DNS-Schichten-Diagramm, Dateizuordnung)
7. **lanCidr** aus Profil ableiten statt `192.168.0.0/16` hardcoden