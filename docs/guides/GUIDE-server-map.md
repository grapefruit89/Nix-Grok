---
meta:
  role: doc
  purpose: Server-Landkarte — alle Services mit ID, Port/Socket, UID, Modul
  docs:
    - docs/adr/011-unified-port-uid-schema.md
    - docs/adr/004-unix-socket-upstreams.md
    - docs/adr/008-nftables-l4-hardening.md
  lib:
    - lib/server-map.nix
    - lib/unix-sockets.nix
    - lib/uid-registry.nix
  tags:
    - server-map
    - ports
    - uid
    - unix-socket
---

# Server-Landkarte (q958) {#guide-server-map}

> **Konvention:** ID = Port = UID = Ordner-Präfix (4-stellig) · Siehe [ADR-011 — Unified Port=UID-Schema](../adr/011-unified-port-uid-schema.md)  
> **Maschinenlesbar:** `lib/server-map.nix` · **Ports:** `modules/00-core/01-core.nix` · **UIDs:** `lib/uid-registry.nix`

## 10-network {#10-network}

| Service | ID | Transport | SSO | Besonderheit |
|---------|-----|-----------|-----|-------------|
| pocket-id | 1001 | UDS `/run/pocket-id/pocket-id.sock` | ja | OIDC-Provider |
| technitium-dns | 1002 | TCP 1002 | nein | Web-UI (Port 53 extern) |
| ddns-updater | 1003 | TCP 1003 | nein | Cloudflare DDNS |
| zigbee2mqtt | 1004 | TCP 1004 | ja | IoT-Frontend |
| blocky | — | ext:53 | nein | DNS-Standard, IANA |
| mqtt | — | ext:1883 | nein | IANA-Standard, IoT |

## 40-observability {#40-observability}

| Service | ID | Transport | SSO | Besonderheit |
|---------|-----|-----------|-----|-------------|
| grafana | 4001 | UDS `/run/grafana/grafana.sock` | ja | Dashboards |
| loki | 4002 | TCP 4002 | nein | intern, kein Caddy |
| gatus | 4003 | UDS `/run/gatus/gatus.sock` | ja | Healthchecks |
| crowdsec | 4004 | TCP 4004 | nein | LAPI intern |
| scrutiny | 4005 | TCP 4005 | ja | SMART-Dashboard |

## 50-media {#50-media}

| Service | ID/UID | Transport | SSO | Besonderheit |
|---------|--------|-----------|-----|-------------|
| jellyfin | 5001 | TCP 5001 | ja | QSV iHD, ReadOnly-Media |
| jellyseerr | 5002 | TCP 5002 | ja | Anfragen-UI |
| sonarr | 5003 | TCP 5003 | ja | UID=5003 (skuid) |
| radarr | 5004 | TCP 5004 | ja | UID=5004 (skuid) |
| readarr | 5005 | TCP 5005 | ja | UID=5005 |
| prowlarr | 5006 | TCP 5006 | ja | UID=5006, VPN-NetNS |
| sabnzbd | 5007 | TCP 5007 | ja | UID=5007, VPN-NetNS |
| audiobookshelf | 5008 | TCP 5008 | ja | |

> *arr (Servarr/.NET) und Jellyfin unterstützen keine Unix Domain Sockets — bleiben TCP ([ADR-004 Konsequenzen](../adr/004-unix-socket-upstreams.md#konsequenzen)).

## 60-apps {#60-apps}

| Service | ID | Transport | SSO | Besonderheit |
|---------|-----|-----------|-----|-------------|
| vaultwarden | 6001 | UDS `/run/vaultwarden/vaultwarden.sock` | ja | |
| homepage | 6002 | UDS `/run/homepage/homepage.sock` | ja | |
| paperless | 6003 | UDS `/run/paperless/paperless.sock` | ja | |
| n8n | 6004 | TCP 6004 | ja | |
| filebrowser | 6005 | TCP 6005 | ja | |
| linkwarden | 6006 | UDS `/run/linkwarden/linkwarden.sock` | ja | |
| open-webui | 6007 | UDS `/run/open-webui/open-webui.sock` | ja | |

## 70-forge {#70-forge}

| Service | ID | Transport | SSO | Besonderheit |
|---------|-----|-----------|-----|-------------|
| forgejo | 7001 | UDS `/run/forgejo/forgejo.sock` | ja | Git |
| semaphore | 7002 | UDS `/run/semaphore/semaphore.sock` | ja | Ansible UI |
| cockpit | 7003 | TCP 7003 | nein | System-Admin |
| amp | 7004 | TCP 7004 | nein | AMP Panel |

## Infrastruktur (kein Caddy) {#infrastruktur}

| Service | Transport | Besonderheit |
|---------|-----------|-------------|
| postgresql | UDS `/run/postgresql/.s.PGSQL.5432` | intern |
| valkey | UDS `/run/redis-valkey/valkey.sock` | RESP2, kein TCP |
| tailscale | ext (VPN) | MagicDNS + Exit-Node |
| ssh | ext:22 | IANA, Impermanence |

## Neue Services einbinden {#neue-services}

1. Ordner-Präfix bestimmen (z.B. `60-apps` → `60xx`)
2. Nächste freie Nummer in `my.ports.*` belegen
3. Bei UDS-fähigem Service: Eintrag in `lib/unix-sockets.nix`
4. `lib/server-map.nix` aktualisieren
5. ADR anlegen falls Architektur-Entscheidung nötig

## Debugging {#debugging}

```bash
# TCP-Ports prüfen
ss -tlnp | grep -E '100[0-9]|[4-7]00[0-9]'

# Unix Sockets prüfen
ls -la /run/{grafana,forgejo,pocket-id,gatus,vaultwarden,paperless,linkwarden,open-webui,homepage,semaphore}/

# Caddy Upstream testen (UDS)
curl --unix-socket /run/grafana/grafana.sock http://localhost/api/health

# *arr UID prüfen
id sonarr radarr readarr prowlarr sabnzbd
```

## Siehe auch {#siehe-auch}

- [ADR-011 — Unified Port=UID-Schema](../adr/011-unified-port-uid-schema.md) — Warum ID = Port = UID = Ordner-Präfix
- [ADR-004 — Unix-Socket-Upstreams](../adr/004-unix-socket-upstreams.md) — welche Services UDS vs. TCP nutzen
- [ADR-008 — nftables L4-Härtung](../adr/008-nftables-l4-hardening.md) — `skuid`-Regeln die UIDs aus dieser Tabelle nutzen
- [GUIDE-nftables-hardening.md#skuid](GUIDE-nftables-hardening.md#skuid) — skuid-Micro-Segmentierung pro Service
