---
meta:
  role: doc
  purpose: Rollout-Stufen und Feature-Roadmap q958
  tags:
    - roadmap
    - rollout
---

# Nix-Grok q958 — Roadmap

Steuerung: `machines/q958/profile.nix` → `rollout.stufe` (eine Zahl, rebuild, testen).

**Aktuell: Stufe 8** (nftables, CrowdSec, fail2ban)

---

## mynixos-v5 Übernahme (grapefruit89/mynixos-v5)

Quelle: Portierung bewährter Patterns ohne 5-Schichten-Bruch. **`.enable` bleibt nur in `rollout.nix`.**

| Prio | Thema | Status | Pfade |
|------|-------|--------|-------|
| 1 | Service-Spec + Port-Duplikat-Assertion | [x] | `lib/services-spec.nix`, `modules/05-services-spec.nix` |
| 2 | Tier-C-Policy-Assertions | [x] | `lib/storage-policy.nix`, `modules/05-storage-policy.nix` |
| 3 | Forbidden-tech subset (Docker/Cron/iptables) | [x] | `lib/forbidden-tech.nix`, `modules/05-forbidden-tech.nix` |
| 4 | `mkService` + `persistDirs` | [x] | `lib/service-factory.nix` → `impermanence.extraPaths`; `tierAStatic` nur Infra |
| 5 | Caddy-Ingress aus Spec (keine Fallback-vHosts) | [x] | `lib/caddy-ingress.nix` inkl. Jellyfin/Vaultwarden |
| 6 | `runtime-guard.nix` ab Stufe 8 | [x] | lockdown + fail2ban + crowdsec live checks |
| 7 | VPN-NetNS Usenet-Stack | [x] | `modules/10-vpn-confinement.nix` (Stufe 6+, ersetzt UID-Routing) |
| 8 | `mkStreamer` Jellyfin | [x] | `lib/service-factory.nix`, `jellyfin.nix` |
| 9 | SOPS nach v5-Muster | [~] | `modules/05-sops.nix` + flake `sops-nix` — aktiv ab Stufe 9 |

**Bewusst nicht übernommen:** dendritisches Auto-Import, `registry.nix`-Defaults, Tailscale-Verbot, Caddy `dynamic_dns`, NIXMETA 2.0.

---

## Legende

- [x] erledigt / fest verworfen
- [ ] offen
- [~] teilweise

---

## Verworfen — nicht wieder aufgreifen

| Was | Warum |
|-----|-------|
| Geo/ASN/MaxMind in **Caddy** | Eine Wahrheit: **nur nftables L4** (`modules/15-firewall.nix`) |
| fwknop / Port-Knocking | Self-Lockout, KISS-Verstoß |
| caddy-security / AuthCrunch | Pocket-ID + `forward_auth` reicht |
| transform-encoder Apache-Logs | JSON + journald |
| mTLS-Turm (Grok widerspricht Tailscale) | `tailscale_admin` + LAN |
| Traefik 55k (Unraid USB) | Vorgeschichte, nicht im Repo |
| Claude nix_os Prompt-XML | Prompt-Engineering |
| DeepSeek auto-locale | Nicht reproduzierbar |
| **Pocket-ID vor Jellyfin-Apps** | Apps: `X-Emby-Authorization` → kein OIDC |

---

## Stufe 5 — Caddy

Quelle: homelab_server USB → `lib/caddy-snippets.nix`

- [x] JSON-Logging
- [x] `forward_auth` → Pocket-ID (Browser-Dienste)
- [x] `auth.*` **ohne** forward_auth (Deadlock-Schutz)
- [x] Blocky before Caddy, Tailscale `--accept-dns=false`
- [x] Gatus `blocky-dns` Gruppe `critical`
- [x] **Jellyfin Client-Split** — Browser → `sso_auth`, Apps → `X-Emby-Authorization`
- [x] `streamer_headers` + `flush_interval -1` + `keepalive off`
- [x] Rebuild testen: `systemctl status caddy blocky`
- [ ] Forward-Auth-Cache ~5 min (Performance, nicht Survival)
**Caddy macht:** TLS, Reverse-Proxy, SSO für Browser-Apps, Streaming-Headers.  
**Caddy macht NICHT:** Geo, Rate-Limit WAN (→ nftables), Adblock (→ Blocky).

---

## Auth-Matrix — wer bekommt was?

Ziel: „LAN = WAN überall `sso_auth`“. **Jellyfin-Apps** sind die Ausnahme (kein OIDC).

| Dienst | LAN (du, Fire TV, Handy) | WAN (Internet) | Mechanismus |
|--------|--------------------------|----------------|-------------|
| *arr, Seerr, Paperless, n8n, … | Pocket-ID SSO | Pocket-ID SSO | Caddy `sso_auth` |
| **Jellyfin Browser** | Pocket-ID SSO | Pocket-ID SSO | Caddy `sso_auth` + Jellyfin-Login |
| **Jellyfin Apps** | Jellyfin-Login | Jellyfin-Login | `X-Emby-Authorization` → kein `forward_auth` |
| `auth.*` (Pocket-ID) | direkt | direkt | Kein forward_auth (Deadlock) |
| Gatus, Grafana, SABnzbd | Tailscale/LAN only | 403 | `tailscale_admin` |

**Jellyfin Client-Split (festgehalten):**

1. **Ein vHost** `jellyfin.nix.m7c5.de` — gleiche URL für Browser und Apps.
2. **Matcher** `@jellyfin_client header_regexp X-Emby-Authorization (?i)MediaBrowser` — offizieller Jellyfin-Client-Header (Fire TV, iOS, Android).
3. **Apps:** `handle @jellyfin_client` → direkt `reverse_proxy`.
4. **Browser:** `handle` → `import sso_auth` → `reverse_proxy`.
5. **LAN:** Blocky-Rewrite `*.nix.m7c5.de` → `192.168.2.73`.
6. **WAN-Schutz:** nftables Geo + Rate-Limits (Stufe 8).

Code: `modules/50-media/jellyfin.nix`.

---

## VPN — Usenet (Stufe 6)

**Entscheidung:** Privado WireGuard **nur** SABnzbd + Prowlarr. Sonarr/Radarr **ohne** VPN (lokal).

| Dienst | VPN | Warum |
|--------|-----|-------|
| **Prowlarr** | ja | Indexer-APIs nach außen |
| **SABnzbd** | ja | Usenet-Download |
| Sonarr / Radarr | nein | Nur lokal → Prowlarr/SAB |
| Jellyfin | nein | Streaming, Apps |

- [x] Kill-Switch `lib/vpn-killswitch.nix`
- [x] `table=off` + UID-Policy-Routing (969, 984)
- [x] `privado-vpn.enable = erstAb 6`
- [x] Rebuild Stufe 6 + VPN-Test (Key rotieren nach Test)

---

## Stufe 6 — Media

- [ ] `rollout.stufe = 6` nach Caddy-Stabilität
- [x] arr-Factory, SAB Kill-Switch, SceneNZBs idempotent
- [ ] Unraid-Cutover (`docs/unraid-migration-map.md`)

---

## Stufe 8 — nftables (Geo + Härte)

Aktivierung: `rollout.stufe >= 8` → `my.security.firewall.enable`

### Was nftables kann (Arbeitstier)

| Feature | q958 | Hinweis |
|---------|------|---------|
| **Geo-Block L4** | [x] vorbereitet | ipdeny.com → `geoip_blocked` Set, wöchentlich |
| **LAN bypass** | [x] | LAN-CIDR vor Geo — Jellyfin/Apps ungestört |
| **Rate-Limit** | [x] | SSH 10/min, HTTP(S) 100/min (WAN) |
| **SYN-Flood** | [x] | Kernel, vor Caddy |
| **CrowdSec Sets** | [~] | Sets da, CrowdSec Stufe 8 |
| **Connection tracking** | [x] | established/related |
| **Adblock** | **nein** | → **Blocky** (DNS), nicht nftables |

### Was nftables NICHT kann

- Hostname-/Domain-Block (→ Blocky)
- HTTPS-Inspektion (→ bräuchte Proxy)
- Pocket-ID / App-Auth (→ Caddy + Jellyfin)

### Erweiterungen (optional, Stufe 8+)

| Idee | Nutzen | Status |
|------|--------|--------|
| CrowdSec → `crowdsec_blocked_*` Sets | Dynamische IP-Bans aus Logs | [~] Sets da, Bouncer Stufe 8 |
| fail2ban + Caddy JSON | SSH/Brute-Force | [ ] Checkliste |
| Pro-Service Port-Limits | z. B. nur 443/80/SSH von außen | [x] Basis |
| `limit`/`meter` Sets mit Timeout | Auto-Expire nach Rate-Limit | [x] SSH/Web |
| Threat-Intel-Feeds (Spamhaus DROP) | Zusätzlich zu Geo | [ ] optional |
| Flowtable / offload | Performance bei hohem Traffic | [ ] Homelab overkill |
| QoS (`mangle`/`flow`) | Streaming-Priorität | [ ] später |

**Adblock in nftables?** Nur grob (IP-Blocklisten wie `0.0.0.0/32`-Tricks) — **schlecht** für Werbung (Domains wechseln, CDN-IPs shared). **Blocky** ist der richtige Layer.

### Cloudflare-Falle

Orange Cloud: `saddr` = CF-Edge (meist DE) → **L4-Geo blind**.  
Lösungen: graue Wolke (DNS-only) **oder** Geo-Regeln in Cloudflare Dashboard.

### Stufe-8 Checkliste

- [ ] `blockedCountries` in `profile.nix` feinjustieren (Default: cn ru kp ir sy vn)
- [ ] `lanCidrs` prüfen (Default RFC1918)
- [ ] `allowLanDns = true` — Fritzbox DHCP DNS → `192.168.2.73`
- [ ] Timer `nftables-geoip-update` nach Boot prüfen
- [ ] fail2ban + Caddy JSON
- [ ] Gatus-Alert wenn Geo-Update fehlschlägt (optional)
- [ ] **Kein** Geo-Snippet in Caddy hinzufügen (Policy)

---

## Blocky — LAN-DNS für alle Geräte

**Ja** — Fritzbox, Fire TV, Handy, alles im LAN kann Blocky als DNS nutzen:

1. Fritzbox/DHCP: primärer DNS = `192.168.2.73` (q958)
2. Firewall: UDP/TCP 53 von LAN erlauben (`allowLanDns` in `15-firewall.nix`)
3. Blocky: Rewrites + (geplant) Adblock-Listen

**Hinweis Stufe 5:** Vor Stufe 8 ist nur SSH in `networking.firewall` offen — **LAN-DNS zu Blocky erst mit Stufe 8** (nftables) oder früherem Port-53-Öffnen für LAN.

Bereits aktiv (Stufe 2):

- [x] Split-DNS / Rewrites (`*.nix.m7c5.de` → LAN-IP) — `modules/10-network.nix`
- [x] Bootstrap 1.1.1.1 (unabhängig von sich selbst)
- [x] `before caddy`, Restart=always, Gatus critical

Noch offen:

- [ ] **Adblock-Listen** in Blocky (`blocking.blackLists` — z. B. OISD, HaGeZi)
- [ ] Router DHCP auf q958-DNS umstellen
- [ ] Test Fire-TV: `nslookup jellyfin.nix.m7c5.de` → `192.168.2.73`
- [ ] Test Adblock: Werbe-Domain → `0.0.0.0` / NXDOMAIN

---

## Stufe 9 — Production

- [x] `/var/lib/pocket-id` in Impermanence-Pfade vorbereitet
- [ ] Impermanence aktiv, SOPS, Dev-Secrets raus

---

## Wissens-SSoT

- [x] `chat_insights_seed.json` — homelab Kirschen, unraid nur Vorlage
- [ ] SQLite + vec Embeddings (Ollama)

---

## Morgen — DRINGEND: Domain + Cloudflare

**Status: noch nicht korrekt eingestellt.** Code/Blocky-Rewrites sind vorbereitet (`nix.m7c5.de`), aber **DNS bei Cloudflare und Router fehlen**.

Policy: **immer graue Wolke (DNS-only)** — kein Orange-Proxy (TOS + nftables-Geo blind).

Checkliste Cloudflare Dashboard (`m7c5.de` Zone):

- [ ] A-Record `nix.m7c5.de` → öffentliche WAN-IP (grau)
- [ ] A-Record `*.nix.m7c5.de` → gleiche WAN-IP (Wildcard, grau)
- [ ] Alle Subdomains **Proxy aus** (DNS only)
- [ ] Kein Apex `m7c5.de` — erst wenn verfügbar; aktuell nur `nix.m7c5.de`
- [ ] TTL sinnvoll (Auto oder 300s für ersten Test)
- [ ] Von außen: `dig jellyfin.nix.m7c5.de` → WAN-IP (nicht CF-Edge wenn grau)

Checkliste LAN (Fritzbox):

- [ ] DHCP primärer DNS → `192.168.2.73` (Blocky auf q958)
- [ ] Test LAN: `nslookup jellyfin.nix.m7c5.de` → `192.168.2.73` (Blocky-Rewrite)
- [ ] Test WAN/LTE: gleicher Hostname → WAN-IP

Nach DNS live:

- [ ] Caddy ACME/TLS prüfen (`systemctl status caddy`, Zertifikat für `*.nix.m7c5.de`)
- [ ] `auth.nix.m7c5.de` erreichbar (Pocket-ID)
- [ ] Erst dann Jellyfin/Caddy-End-to-End testen

---

## Nächste Schritte (Reihenfolge)

1. [ ] **Morgen:** Cloudflare + Fritzbox-DNS (siehe oben) — **blockiert alles Domain-bezogene**
2. [ ] `nixos-rebuild switch` — Jellyfin ohne SSO + Firewall-Module prüfen
3. [ ] Jellyfin testen: Fire-TV `jellyfin.nix.m7c5.de` + Browser (Pocket-ID zuerst)
4. [ ] Wenn WAN-Härtung: `rollout.stufe = 8` (nftables Geo — **nicht** Caddy)
5. [ ] Forward-Auth-Cache (optional)
6. [ ] Stufe 6 Media-Cutover