---
meta:
  role: doc
  purpose: Betriebsguide Media-Stack, VPN-NetNS, Config-Sync, QSV
  date: 2026-07-10
  status: current
  docs:
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/2009-vpn-leak-check.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/011-unified-port-uid-schema.md
    - docs/guides/GUIDE-dendritic-architecture.md
    - docs/guides/GUIDE-auth-stack.md
  tags:
    - media
    - jellyfin
    - jellyseerr
    - vpn
---

# Media Stack Guide {#guide-media-stack}

> Native systemd-*arr, Jellyfin QSV, VPN-NetNS, `media-stack-config-sync`.

## Dendritische Dateien {#dateien}

| Datei | Dienste |
|-------|---------|
| `52-arr.nix` | Sonarr, Radarr, Readarr, Lidarr, Prowlarr |
| `53-sabnzbd.nix` | SABnzbd (VPN-NetNS) |
| `51-jellyfin.nix` | Jellyfin + Jellyseerr |
| `54-audiobookshelf.nix` | Audiobookshelf |
| `55-navidrome.nix` | Navidrome |
| `56-arr-sync/` | Locale/API-Sync (locale, prowlarr, download-clients) |

`.enable` nur in `machines/q958/rollout.nix` (ab Stufe 6) — Konvention aus [GUIDE-dendritic-architecture.md](GUIDE-dendritic-architecture.md).

## VPN-NetNS {#vpn-netns}

- Namespace `usenet`: WireGuard + nftables Kill-Switch
- veth-Bridge: Host `192.168.15.5` ↔ NS `192.168.15.1`
- Prowlarr/SABnzbd im NS; Sonarr/Radarr auf Host
- Leak-Check: [ADR-2009 — VPN-Leak-Check](../adr/2009-vpn-leak-check.md)

```bash
systemctl status usenet.service
systemctl start vpn-netns-test    # wenn vpnTest.enable
journalctl -u vpn-leak-check.service -n 20
```

## Jellyfin {#jellyfin}

- Config-Seeds: `modules/50-media/data/jellyfin-{system,network}.xml` (nur wenn fehlend)
- Media RO: `/data/media` read-only in systemd unit
- OOM-Schutz: MemoryMax 12G per [ADR-003](../adr/003-oom-cgroup-limiting.md#tier-modell)

## Jellyseerr {#jellyseerr}

Anfragen-Manager für den Media-Stack. Läuft in `51-jellyfin.nix` (gleiche Datei wie Jellyfin).

- Port: 5002 (`my.ports.jellyseerr`), State: `/var/lib/seerr`
- NixOS-Service: `services.seerr` (nixpkgs upstream)
- **Auth: Jellyfin-eigene Session** — kein Pocket-ID OIDC (User-Accounts werden aus Jellyfin importiert)
- Kein Unix-Socket-Support — TCP auf localhost
- Healthcheck ohne Auth: `GET /api/v1/settings/public`
- Radarr/Sonarr-Verbindungen: nur via Web-UI konfigurierbar (kein deklarativer Dateimechanismus)

Warum kein OIDC: → [GUIDE-auth-stack.md#jellyseerr](GUIDE-auth-stack.md#jellyseerr)

## *arr (Sonarr/Radarr/Readarr/Prowlarr) {#arr}

- UIDs: 5003–5007 nach [ADR-011 Port=UID-Schema](../adr/011-unified-port-uid-schema.md)
- Media RO: `/data/media` nur `ReadOnlyPaths` — Schutz vor versehentlichem Löschen auf Tier C
- Downloads RW: `/data/downloads` (Tier B Cache) — Import/Hardlink-Staging
- MediaCover: Bind-Mounts nach `/mnt/fast_pool/metadata/{sonarr,radarr,readarr,prowlarr}`
- QSV: `LIBVA_DRIVER_NAME=iHD`, Gruppen `video` + `render`
- Caddy: X-Emby-Authorization-Bypass für Clients (kein User-Agent-Bypass)

## MediaCover (Tier B) {#mediacover}

Bind-Mounts nach `/mnt/fast_pool/metadata/{sonarr,radarr,prowlarr}` — verhindert Tier-A-Bloat und beschleunigt Restic.

## Config-Sync {#config-sync}

```bash
systemctl restart media-stack-config-sync
journalctl -u media-stack-config-sync -n 50
```

Sync wartet auf APIs (`wait-for-api.nix`), nutzt VPN-Adressen für Prowlarr (`VPN_NS_ADDRESS`).
Bei Timeout: VPN-NetNS und Bridge-Routen prüfen.

## Qualitätsprofile {#qualitaetsprofile}

Sync migriert bei `language = "de"`:

- Sonarr: Profil 4 → 1 (Deutsch)
- Radarr: Profil 11 → 4 (Fernseher)

Bulk-Import per curl: siehe nix-hermes `jellyfin_configs/*.json` (manuell, kein Flake-Input)

## Siehe auch {#siehe-auch}

- [ADR-007 — Dendritische Module](../adr/007-dendritic-one-file-per-service.md) — Eine-Datei-pro-Dienst Konvention
- [ADR-2009 — VPN-Leak-Check](../adr/2009-vpn-leak-check.md) — Leak-Detection für Prowlarr/SABnzbd im NetNS
- [ADR-003 — OOM-Isolation](../adr/003-oom-cgroup-isolation.md) — MemoryMax für Jellyfin (12G), SABnzbd, *arr
- [ADR-011 — Port=UID-Schema](../adr/011-unified-port-uid-schema.md) — UIDs 5001–5008 für Media-Services
- [GUIDE-dendritic-architecture.md](GUIDE-dendritic-architecture.md) — Architektur-Konventionen hinter `50-media/`
- [GUIDE-auth-stack.md](GUIDE-auth-stack.md) — Auth-Matrix, Jellyfin-Client-Split, Jellyseerr Auth
- [RUNBOOK.md#arr-apps](../RUNBOOK.md#arr-apps) — Quick-Fix bei *arr .env / MediaCover-Problemen
