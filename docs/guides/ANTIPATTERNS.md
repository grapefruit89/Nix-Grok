---
meta:
  role: doc
  purpose: Verbotene Muster — Synthese aus nix-hermes Guides
  tags:
    - antipattern
    - architecture
---

# Antipatterns

> Explizit **nicht** im q958-Repo — portiert aus nix-hermes `Guides/ANTIPATTERN-*`.

## Legacy iptables-Firewall

`networking.firewall.enable = true` (iptables-Backend) statt nativem nftables.  
**Stattdessen:** `modules/15-firewall.nix` + `lib/nftables-rules.nix` — siehe [GUIDE-nftables-hardening](GUIDE-nftables-hardening.md).

## Externe Media-Flakes (Nixarr/Nixflix als Input)

Flake-Inputs für *arr-Stacks erzeugen Versions-Drift und widersprechen AGENTS.md.  
**Stattdessen:** native Module in `modules/50-media/`, Sync-Logik in `sync-script.sh`.

## Socat-UDS-Bridges für Caddy

Umweg über TCP statt Unix-Socket-Upstreams.  
**Stattdessen:** [ADR-004](../adr/004-unix-socket-upstreams.md).

## Kopia statt Restic

**Stattdessen:** `services.restic.backups` in `30-storage.nix`.

## Thymis / NIXMETA-Auto-Import

Automatische Modul-Discovery aus Kommentar-Headern — Build-Kosten und Magic.  
**Stattdessen:** explizite Imports in `machines/q958/default.nix`, File-Meta nur für KI-Index.

## SSH-Rescue auf Production-Port

Rescue-SSH auf demselben Port wie Production-SSH.  
**Stattdessen:** Dropbear 2222, Production 53844 (Stufe 9).

## Logs auf tmpfs ohne Journal-Persist

Bei Impermanence Journal verlieren.  
**Stattdessen:** bind-mount `/var/log/journal` → `/persist/var/log/journal`.

## Bastelmodus (imperative Overrides)

`nix-env`, manuelle `/etc`-Edits, `systemctl edit` ohne Nix-Commit.  
**Stattdessen:** `rollout.stufe` erhöhen, rebuild, testen.

## User-Agent Jellyfin-Bypass

Unsicher und fragil.  
**Stattdessen:** `X-Emby-Authorization` Regex in `jellyfin.nix`.