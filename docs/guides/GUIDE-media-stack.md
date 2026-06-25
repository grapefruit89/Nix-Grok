---
meta:
  role: doc
  purpose: Betriebsguide Media-Stack, VPN-NetNS, Config-Sync, QSV
  docs:
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/009-vpn-leak-check.md
    - docs/guides/GUIDE-dendritic-architecture.md
  tags:
    - media
    - jellyfin
    - vpn
---

# Media Stack Guide

> Native systemd-*arr, Jellyfin QSV, VPN-NetNS, `media-stack-config-sync`.

## Dendritische Dateien

| Datei | Dienste |
|-------|---------|
| `sonarr-radarr.nix` | Sonarr + Radarr (gemeinsam) |
| `prowlarr.nix`, `sabnzbd.nix` | VPN-NetNS (`usenet`) |
| `jellyfin.nix` | Jellyfin + Jellyseerr |
| `sync.nix` + `sync-script.sh` | Locale/API-Sync oneshot |

`.enable` nur in `machines/q958/rollout.nix` (ab Stufe 6).

## VPN-NetNS

- Namespace `usenet`: WireGuard + nftables Kill-Switch
- veth-Bridge: Host `192.168.15.5` ↔ NS `192.168.15.1`
- Prowlarr/SABnzbd im NS; Sonarr/Radarr auf Host
- Leak-Check: [ADR-009](../adr/009-vpn-leak-check.md)

```bash
systemctl status usenet.service
systemctl start vpn-netns-test    # wenn vpnTest.enable
journalctl -u vpn-leak-check.service -n 20
```

## Jellyfin

- Config-Seeds: `modules/50-media/data/jellyfin-{system,network}.xml` (nur wenn fehlend)
- Media RO: `/data/media` read-only in systemd unit

## *arr (Sonarr/Radarr/Readarr/Prowlarr)

- Media RO: `/data/media` nur `ReadOnlyPaths` — Schutz vor versehentlichem Löschen auf Tier C
- Downloads RW: `/data/downloads` (Tier B Cache) — Import/Hardlink-Staging
- MediaCover: Bind-Mounts nach `/mnt/fast_pool/metadata/{sonarr,radarr,readarr,prowlarr}`
- QSV: `LIBVA_DRIVER_NAME=iHD`, Gruppen `video` + `render`
- Caddy: X-Emby-Authorization-Bypass für Clients (kein User-Agent-Bypass)

## MediaCover (Tier B)

Bind-Mounts nach `/mnt/fast_pool/metadata/{sonarr,radarr,prowlarr}` — verhindert Tier-A-Bloat und beschleunigt Restic.

## Config-Sync

```bash
systemctl restart media-stack-config-sync
journalctl -u media-stack-config-sync -n 50
```

Sync wartet auf APIs (`wait-for-api.nix`), nutzt VPN-Adressen für Prowlarr (`VPN_NS_ADDRESS`).  
Bei Timeout: VPN-NetNS und Bridge-Routen prüfen.

## Qualitätsprofile

Sync migriert bei `language = "de"`:

- Sonarr: Profil 4 → 1 (Deutsch)
- Radarr: Profil 11 → 4 (Fernseher)

Bulk-Import per curl: siehe nix-hermes `jellyfin_configs/*.json` (manuell, kein Flake-Input).