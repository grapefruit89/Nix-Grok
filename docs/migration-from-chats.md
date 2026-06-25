---
meta:
  role: doc
  purpose: Migrationsnotizen aus Chat-Verlauf
  tags:
    - migration
    - notes
---

# Kirschen aus USB-Chats

Quelle: `/mnt/usbinspect/neuesmaterialfuergrok/` auf USB — **nicht** im Git-Repo.  
Im Repo: nur Destillation (`tools/chat_insights_seed.json`, ~30 Zeilen pro Kirsche).

| Thema | Rolle für q958 |
|-------|----------------|
| **homelab_server** | **SSoT für Caddy, Pocket-ID, Blocky, Gleise** |
| **nix_os** | Nix-Grok-Architektur, Rollout, Module |
| **unraid** | **Nur Vorlage** (Inventar, Volumes) → `docs/unraid-migration-map.md` |

Nix-Dateien bleiben autoritativ; diese Notiz ist die menschliche Destillation.

---

## homelab_server — Grok × Claude × DeepSeek

### Thema: Forward-Auth + Pocket-ID

| | Grok | Claude | DeepSeek | q958 |
|---|------|--------|----------|------|
| SPOF | Jeder Request → POST verify; Cache 5 min vorgeschlagen | Pocket-ID down = alle SSO-Dienste tot; auth.* nie hinter forward_auth | — | ✓ `sso_auth` + Keepalive; Cache **offen** |
| Admin Gleis 2 | v9.0: Tailscale **oder** Freeze mTLS (widerspricht sich) | — | — | **Tailscale** `tailscale_admin` (Stufe 2) |

### Thema: Cloudflare + Geo

| | Grok | Claude | DeepSeek | q958 |
|---|------|--------|----------|------|
| Real-IP | CF-Connecting-IP + trusted_proxies | Blocky-Bootstrap 1.1.1.1 für ACME | `trusted_proxies cloudflare` war Root Cause für Geoblock-Bug | Stufe 5/8 |
| Geo | Alles L4 nftables, Caddy-Geo raus | — | Geoblock scheiterte an private_ranges only | Geo → Stufe 8 nftables |

### Thema: Blocky ↔ Caddy

| | Grok | Claude | DeepSeek | q958 |
|---|------|--------|----------|------|
| Boot | — | `before=caddy` + Bootstrap-DNS | — | Bootstrap in `profile.nix` dns |
| Laufzeit | — | **Watchdog + Gatus** — Renewal scheitert still wenn Blocky stirbt | — | **proposed** |
| Impermanence | — | `/var/lib/pocket-id` vor Stufe 9 persistieren | — | Stufe 9 |

### Thema: Streaming (Jellyfin)

| | Grok | Claude | DeepSeek | q958 |
|---|------|--------|----------|------|
| Caddy | — | — | `flush_interval -1` + `keepalive off` | ✓ `streamer_headers` jellyfin.nix |
| Upstream | — | — | Container-Name, nicht 172.18.0.1 | ✓ 127.0.0.1 |

### Verworfen (homelab)

- fwknop SPA (Grok) — zu komplex
- transform-encoder Apache-Logs (Grok) — JSON + journald
- caddy-security / AuthCrunch (Grok) — Pocket-ID reicht
- Grok mTLS-Turm vs Tailscale-Widerspruch → **Tailscale + forward_auth**

### Unraid-Chats

- **55k Traefik-Zeilen** leben nur auf USB (`claude/unraid/`) — **nicht** im Repo
- Caddy-Learnings aus Unraid-Chats sind in **homelab_server** konsolidiert (Tower v9.0)
- Unraid = Inventar/Volumes, siehe `unraid-migration-map.md`

### q958 Ist-Zustand (Caddy, Juni 2026)

| Thema | Status |
|-------|--------|
| `sso_auth` + Keepalive | ✓ `lib/caddy-snippets.nix` |
| Forward-Auth-Cache 5min | offen (Phase 4) |
| Blocky before Caddy | ✓ `10-network.nix` + `60-apps/default.nix` |
| Gatus blocky-dns | ✓ Gruppe `critical` |
| Tailscale MagicDNS | ✓ `--accept-dns=false` |
| Jellyfin Client-Split (X-Emby-Authorization) | ✓ `jellyfin.nix` |
| Cloudflare trusted_proxies | offen (WAN/CF) |
| nftables Geo (nur L4) | ✓ `15-firewall.nix` überarbeitet, Stufe 8 aktivieren |
| Blocky LAN-DNS | ✓ DHCP → q958, Firewall UDP/53 Stufe 8 |

---

## Stufe 5 — Caddy

| Idee | Quelle | Nix-Grok | Context7 |
|------|--------|----------|------------|
| Native `forward_auth` zu Pocket-ID | Grok Tower | ✓ `lib/caddy-snippets.nix` | [Caddy forward_auth](https://caddyserver.com/docs/caddyfile/directives/forward_auth) |
| JSON-Logging | Grok | ✓ `globalConfig` | journald + Loki |
| Forward-Auth-Entlastung (~5 min) | Grok | ~ Keepalive; Cache offen | [Community](https://caddy.community/t/caching-forward-auth-responses/30577) |
| Geo/ASN nur L4 (nftables) | Grok | Stufe 8 | KISS |
| fwknop ablehnen | Grok | ✓ nicht implementiert | zu komplex |
| Admin via Tailscale | Grok | ✓ `tailscale_admin` | passt `tailscaleIP` |

**Implementiert in:** `lib/caddy-snippets.nix`, `modules/10-network.nix`, `40-observability.nix`, `50-media/`

---

## Stufe 6 — Media

| Dienst | Unraid | Nix-Grok |
|--------|--------|----------|
| Pocket-ID, Redis | läuft | Valkey + Pocket-ID ✓ |
| *arr + SABnzbd + Jellyfin | läuft | Stufe 6 |
| Caddy | Docker | Stufe 5 nativ |
| Hermes | Docker | Stufe 7 |

### Goldene Regeln (Prompt-Meta-Kritik)

1. **Idempotente API-Setups** — GET vor POST → ✓ `sync-script.sh`
2. **Factory statt Duplikat** — ✓ `arr-helper.nix`
3. **SABnzbd VPN Kill-Switch** — ✓ `sabnzbd.nix`
4. **Streamer: kein Caddy-Cache, HW-Accel** — ✓ `jellyfin.nix`
5. **Impermanence pro Service** — Stufe 9

---

## Stufe 2/8 — Hardening

| Idee | Quelle | Status |
|------|--------|--------|
| Blocky: `RestrictNamespaces`, `~@mount` | Grok audit | ✓ `10-network.nix` |
| Pocket-ID systemd-hardening | Grok | ✓ erweitert |
| Statische UID-Registry | Grok | Roadmap Stufe 8 |

---

## Bereits richtig (DeepSeek-Roast obsolet)

- Flakes + `flake.lock`
- Hardware nur `machines/q958/`
- Rollout-Stufen
- Antipatterns aus `nixos_docs.db` (Kopia, socat-UDS, Thymis, …)

---

## Bewusst verworfen

| Inhalt | Grund |
|--------|-------|
| Claude v80 Prompt-XML (41k Zeilen) | Prompt-Engineering, kein Nix |
| DeepSeek 102k Roast mynixos-v5 | auto-locale, NMS-Header — nicht q958 |
| Grok mTLS-Turm vs Tailscale-Widerspruch | **Tailscale + forward_auth** gewählt |
| 55k Unraid-Claude Docker-Tuning | nach Stufe 5–6 |

---

## DuckDB → SQLite

- Original `nixos_docs.db` **nie in-place** ändern
- Migration: `tools/migrate-duckdb-to-sqlite.py` → neue `nixos_docs.sqlite`
- MCP später auf SQLite umstellen wenn validiert