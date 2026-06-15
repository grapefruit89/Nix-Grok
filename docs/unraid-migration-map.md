# Unraid → Nix-Grok Migrationskarte

Quelle: `neuesmaterialfuergrok/*/unraid/Docker_Containers.md`  
Unraid: `192.168.2.250` (Tower) → Nix: **q958** `192.168.2.73`

---

## Core (MUSS laufen)

| Unraid Container | Status Unraid | Nix-Grok | Rollout |
|------------------|---------------|----------|---------|
| redis | An | Valkey | Stufe 2 ✓ |
| Pocket-ID | An | `services.pocket-id` | Stufe 2 ✓ |
| homepage | An | `homepage` | Stufe 7 |
| speedtest-tracker | An | — (optional/Gatus) | — |
| caddy-on-steroids | An | `services.caddy` | **Stufe 5** |

---

## Media Frontend

| Unraid | Nix-Grok | Rollout |
|--------|----------|---------|
| Jellyfin | `jellyfin` + HW-QSV | Stufe 6 |
| seerr (Jellyseerr) | `jellyseerr` | Stufe 6 |
| audiobookshelf | — (Readarr/ReadMeABook?) | später |
| ReadMeABook | — | später |

---

## Media Backend (*arr)

| Unraid | Nix-Grok | Rollout |
|--------|----------|---------|
| radarr | `radarr` | Stufe 6 |
| sonarr | `sonarr` | Stufe 6 |
| sabnzbd (+ WireGuard) | `sabnzbd` + `privado-vpn` | Stufe 6 / VPN Key fehlt |
| prowlarr | `prowlarr` | Stufe 6 |
| library-manager | gestoppt | — |

---

## AI

| Unraid | Nix-Grok | Rollout |
|--------|----------|---------|
| hermes-agent | Docker bridge | Stufe 7 `hermes.nix` |
| open-webui | Aus | Stufe 7 optional |
| OpenClaw | Aus | — |
| AnythingLLM | Aus | — |

---

## Tools (gestoppt auf Unraid)

bentopdf, readeck, linkding, Maintainerr — **nicht priorisiert** für erste Migration.

---

## Netzwerk-Mapping

| Unraid | Nix-Grok |
|--------|----------|
| `media-network` 172.18.0.0/16 | localhost + Caddy vHosts |
| `*.m7c5.de` via Caddy Docker | `*.m7c5.de` via native Caddy |
| `auth.m7c5.de` | `auth.m7c5.de` ✓ |

---

## Migrations-Reihenfolge

1. **Stufe 5** — Caddy ersetzt `caddy-on-steroids` (DNS umstellen)
2. **Stufe 6** — *arr-Stack parallel zu Unraid testen
3. **Stufe 7** — Hermes nativ statt Docker
4. Unraid-Container **einzeln** abschalten wenn Nix-Parität OK

---

## Volumes (Unraid → q958 Storage)

| Unraid Host-Pfad | Ziel q958 |
|------------------|-----------|
| `/mnt/docker_and_vm/appdata/*` | `/var/lib/<service>` (Tier A) |
| `/mnt/user/data/media` | `/data/media` oder `/mnt/media` (Tier C) |
| `/mnt/downloadcache` | `/mnt/fast_pool` (Tier B, wenn SATA-SSD da) |

q958 aktuell: **singleDisk** Tier A auf `/dev/sda` — `mergerfsEnable = false` bis Branches existieren.