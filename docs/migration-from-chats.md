# Kirschen aus USB-Chats

Quelle: `/mnt/usbinspect/neuesmaterialfuergrok/` (Grok, Claude, DeepSeek) — ~709k Zeilen, destilliert für **Nix-Grok q958**.

Nix-Dateien bleiben autoritativ; diese Notiz ist die menschliche Destillation.

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