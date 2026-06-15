# Nix-Grok q958 — Roadmap

Rollout-Steuerung: `machines/q958/profile.nix` → `rollout.stufe` (eine Zahl, rebuild, testen).

**Aktuell: Stufe 5** (Caddy Reverse Proxy)

---

## Legende

- [x] erledigt
- [ ] offen
- [~] teilweise / vorbereitet

---

## Stufe 0–4 — Basis ✓

- [x] SSH, Netz, Grok CLI (moritz)
- [x] zram, kernel-slim, boot-safeguard
- [x] PostgreSQL, Valkey, Blocky, Tailscale, Pocket-ID
- [x] Observability: Gatus, Grafana, Loki, Vector
- [x] MCP: context7 + mcp-nixos + nixos_docs (DuckDB)
- [x] GitHub: [grapefruit89/Nix-Grok](https://github.com/grapefruit89/Nix-Grok)

---

## Stufe 5 — Caddy (aktiv)

Quelle: USB-Chats Grok Tower v9.0 → `lib/caddy-snippets.nix`

- [x] `rollout.stufe = 5`
- [x] JSON-Logging (`globalConfig` → journald/Loki)
- [x] `forward_auth` → Pocket-ID `/api/auth/verify`
- [x] `tailscale_admin` für Grafana, Gatus, SABnzbd
- [x] `streamer_headers` + `flush_interval -1` für Jellyfin
- [x] SSO (`sso_auth`) für *arr, Jellyfin, Seerr
- [x] Caddy `.enable` nur via `rollout.nix` (nicht 60-apps)
- [~] Forward-Auth-Cache (~5 min) — Keepalive gesetzt; echter Response-Cache → Stufe 5.1
- [ ] ACME/DNS-01 (Cloudflare) wenn öffentliche `*.m7c5.de` gewünscht
- [ ] Caddy nach Rebuild testen: `systemctl status caddy`, `curl -I https://auth.m7c5.de`

**Bewusst nicht:**

- [x] fwknop (KISS-Verstoß)
- [ ] Geo/ASN in Caddy (→ Stufe 8 nftables L4)

---

## Stufe 6 — Media (Unraid → Nix)

Siehe `docs/unraid-migration-map.md`

- [ ] `rollout.stufe = 6` nach Caddy-Stabilität
- [x] SABnzbd VPN Kill-Switch (`RestrictNetworkInterfaces`)
- [x] Jellyfin HW-Accel (i915 UHD 630)
- [x] Idempotenter SceneNZBs-Indexer (`sync-script.sh` GET vor POST)
- [x] `arr-helper.nix` Factory (kein zweites mkArr)
- [ ] Storage-Tiers / Mounts für `/data/media` (Tier C wenn HDD da)
- [ ] Privado VPN Key in SOPS (aktuell deaktiviert)
- [ ] Restic-Backup *arr-SQLite-DBs
- [ ] Unraid-Container abschalten erst wenn Nix-Parität erreicht

---

## Stufe 7 — Apps

- [ ] Hermes (nativ, nicht Docker)
- [ ] Homepage, Vaultwarden, Paperless, n8n, HA, Zigbee
- [ ] Open WebUI optional

---

## Stufe 8 — Security

- [ ] Firewall (nftables) aktiv
- [ ] fail2ban + Caddy JSON (`caddy-json` Filter vorhanden)
- [ ] Geo/ASN nur L4 (kein doppeltes L7 in Caddy)
- [ ] Statische UID-Registry (wenn nftables UID-Filter)

---

## Stufe 9 — Production

- [ ] Impermanence aktiv
- [ ] Impermanence-Pfade pro Service deklariert (nicht manuell)
- [ ] `my.mode = production`
- [ ] Dev-Secrets aus `profile.nix` entfernen
- [ ] SOPS (`secrets.sops.yaml`)

---

## Wissens-SSoT (parallel)

- [x] DuckDB `nixos_docs.db` read-only MCP (Original USB unberührt)
- [x] `tools/migrate-duckdb-to-sqlite.py` (row-by-row, read-only)
- [x] `tools/build_nixos_knowledge_db.py` — SQLite + **sqlite-vec** + `chat_insights`
- [x] `tools/chat_insights_seed.json` — 16 Kirschen (homelab/nix_os/unraid, pro Agent)
- [ ] Embeddings via Ollama: `--ollama-host http://127.0.0.1:11434` (sonst Zero-Placeholder)
- [ ] MCP auf SQLite umstellen wenn validiert
- [ ] USB-Chats vollständig parsen (Theme×Agent Session mit dir)
- [ ] `build_dbs.py` Forward-Sync aus nix-hermes portieren

```bash
nix-shell -p python3 python3Packages.duckdb sqlite sqlite-vec --run \
  'python3 tools/build_nixos_knowledge_db.py \
    --duckdb ~/.local/share/nix-grok/nixos_docs.db \
    --target data/nixos_docs.sqlite'
```

---

## Nächste Aktionen (Reihenfolge)

1. Rebuild Stufe 5 → Caddy + vHosts testen
2. DNS/`*.m7c5.de` auf q958 (`192.168.2.73`) zeigen lassen
3. Wenn stabil: Stufe 6 Media
4. DuckDB→SQLite Migration testen: `nix-shell -p python3 python3Packages.duckdb --run "python3 tools/migrate-duckdb-to-sqlite.py ~/.local/share/nix-grok/nixos_docs.db data/nixos_docs.sqlite"`