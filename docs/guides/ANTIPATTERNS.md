---
meta:
  role: doc
  purpose: Verbotene Muster — Synthese aus nix-hermes Guides
  docs:
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/012-modern-cli-tools.md
    - docs/adr/004-unix-socket-upstreams.md
    - docs/adr/008-nftables-l4-hardening.md
  tags:
    - antipattern
    - architecture
---

# Antipatterns {#antipatterns}

> Explizit **nicht** im q958-Repo — portiert aus nix-hermes `Guides/ANTIPATTERN-*`.

## Legacy iptables-Firewall {#iptables}

`networking.firewall.enable = true` (iptables-Backend) statt nativem nftables.  
**Stattdessen:** `modules/15-firewall.nix` + `lib/nftables-rules.nix` — siehe [ADR-008](../adr/008-nftables-l4-hardening.md) und [GUIDE-nftables-hardening](GUIDE-nftables-hardening.md).

## Externe Media-Flakes (Nixarr/Nixflix als Input) {#media-flakes}

Flake-Inputs für *arr-Stacks erzeugen Versions-Drift und widersprechen AGENTS.md.  
**Stattdessen:** native Module in `modules/50-media/`, Sync-Logik in `sync-script.sh` — [ADR-007](../adr/007-dendritic-one-file-per-service.md).

## Socat-UDS-Bridges für Caddy {#socat-uds}

Umweg über TCP statt Unix-Socket-Upstreams.  
**Stattdessen:** [ADR-004 — Unix-Socket-Upstreams](../adr/004-unix-socket-upstreams.md).

## Kopia statt Restic {#kopia}

**Stattdessen:** `services.restic.backups` in `30-storage.nix` — [GUIDE-data-management.md](GUIDE-data-management.md).

## Thymis / NIXMETA-Auto-Import {#nixmeta}

Automatische Modul-Discovery aus Kommentar-Headern — Build-Kosten und Magic.  
**Stattdessen:** explizite Imports in `machines/q958/default.nix`, File-Meta nur für KI-Index ([ADR-007](../adr/007-dendritic-one-file-per-service.md)).

## SSH-Rescue auf Production-Port {#ssh-rescue}

Rescue-SSH auf demselben Port wie Production-SSH.  
**Stattdessen:** Dropbear 2222, Production 53844 (Stufe 9) — [GUIDE-security-secrets.md#notfall](GUIDE-security-secrets.md#notfall).

## Logs auf tmpfs ohne Journal-Persist {#tmpfs-logs}

Bei Impermanence Journal verlieren.  
**Stattdessen:** bind-mount `/var/log/journal` → `/persist/var/log/journal` ([GUIDE-storage-tiers.md#impermanence](GUIDE-storage-tiers.md#impermanence)).

## Bastelmodus (imperative Overrides) {#bastelmodus}

`nix-env`, manuelle `/etc`-Edits, `systemctl edit` ohne Nix-Commit.  
**Stattdessen:** `rollout.stufe` erhöhen, rebuild, testen ([ADR-012](../adr/012-modern-cli-tools.md)).

## User-Agent Jellyfin-Bypass {#jellyfin-bypass}

Unsicher und fragil.  
**Stattdessen:** `X-Emby-Authorization` Regex in `jellyfin.nix`.

## Siehe auch {#siehe-auch}

- [ADR-007 — Dendritische Module](../adr/007-dendritic-one-file-per-service.md) — warum keine Monolith-Stacks oder Auto-Imports
- [ADR-004 — Unix-Socket-Upstreams](../adr/004-unix-socket-upstreams.md) — warum kein Socat-Umweg
- [ADR-008 — nftables L4-Härtung](../adr/008-nftables-l4-hardening.md) — warum kein legacy iptables
- [ADR-012 — Moderne CLI-Tools](../adr/012-modern-cli-tools.md) — Tooling-Entscheidungen und DX-Standards
- [GUIDE-dendritic-architecture.md](GUIDE-dendritic-architecture.md) — die richtige Architektur statt Antipatterns
