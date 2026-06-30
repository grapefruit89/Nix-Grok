---
meta:
  role: doc
  purpose: Server-Landkarte — alle Services mit ID, Port/Socket, UID, Ist-Status
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

> **Konvention:** ID = Port = UID = Ordner-Präfix (4-stellig)
> · Quelle der Wahrheit: [`lib/server-map.nix`](../../lib/server-map.nix)
> · Ports: [`modules/00-core/01-core.nix`](../../modules/00-core/01-core.nix)
> · UIDs: [`lib/uid-registry.nix`](../../lib/uid-registry.nix)
> · ADR: [ADR-011 — Unified Port=UID-Schema](../adr/011-unified-port-uid-schema.md)

## Inhaltsverzeichnis {#toc}

- [Status-Legende](#status-legende)
- [10-network](#10-network)
- [40-observability](#40-observability)
- [50-media](#50-media)
- [60-apps](#60-apps)
- [70-home-automation](#70-home-automation)
- [70-forge](#70-forge)
- [Infrastruktur (kein Caddy)](#infrastruktur)
- [Socket-Migration — Offene Lücken](#socket-migration)
- [Neuen Service einbinden](#neue-services)
- [Debugging](#debugging)
- [Siehe auch](#siehe-auch)

---

## Status-Legende {#status-legende}

| Symbol | Bedeutung |
|--------|-----------|
| `🟢 UDS` | Unix Domain Socket — Socket-Datei existiert, Caddy routet darüber |
| `🎯 UDS*` | UDS in `server-map.nix` geplant — läuft noch TCP, Migration offen |
| `🔵 TCP-L` | TCP `127.0.0.1:PORT` — localhost-only, hinter Caddy |
| `⚠️ TCP-W` | TCP wildcard `0.0.0.0` oder `[::]` — Security-Problem, TODO |
| `🌐 ext` | Externer Port (IANA-Standard, Protokoll, Firewall) — nicht ändern |
| `🔒 intern` | Nur intern, kein Caddy-Proxy |

---

## 10-network {#10-network}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| [pocket-id](../../modules/10-network/11-network.nix) | 1001 | — | `⚠️ TCP-W :1001` → Ziel: `🎯 UDS /run/pocket-id/pocket-id.sock` | ja | OIDC-Provider |
| technitium-dns | 1002 | — | `🔵 TCP-L :1002` | nein | Web-UI (Port 53 ext.) |
| ddns-updater | 1003 | — | `🔵 TCP-L :1003` | nein | Cloudflare DDNS |
| blocky/DNS | — | — | `🌐 ext :53` | nein | IANA-Standard |
| mqtt (mosquitto) | — | — | `🌐 ext :1883` | nein | IoT, IANA |

> **pocket-id** lauscht derzeit auf `*:1001` (alle Interfaces). Da Caddy der einzige legitime Client ist,
> sollte es auf `127.0.0.1` oder UDS eingeschränkt werden.
> Netbird-OIDC nutzt `http://127.0.0.1:1001/` — TCP-L wäre ausreichend.

---

## 40-observability {#40-observability}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| [grafana](../../modules/40-observability/42-logging.nix) | 4001 | — | `🟢 UDS /run/grafana/grafana.sock` | ja | Dashboards + Loki-UI |
| loki | 4002 | — | `⚠️ TCP-W :4002` | nein | Intern (Vector→Loki→Grafana) |
| [gatus](../../modules/40-observability/41-gatus.nix) | 4003 | — | `🎯 UDS* /run/gatus/gatus.sock` | ja | Healthchecks |
| crowdsec | 4004 | — | `🔵 TCP-L :4004` | nein | LAPI intern |
| scrutiny | 4005 | — | `🔵 TCP-L :4005` | ja | SMART-Dashboard |
| victoriametrics | 4006 | — | `🔵 TCP-L :4006` | nein | Metriken intern |

> **loki** auf `*:4002` ist ein Fehler — Loki ist ein reiner Interna-Service.
> Fix: `http_listen_address: 127.0.0.1` in der Loki-Konfiguration setzen.

---

## 50-media {#50-media}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| [jellyfin](../../modules/50-media/jellyfin.nix) | 5001 | 5001 | `⚠️ TCP-W :5001` | ja | QSV iHD · ReadOnly-Media |
| jellyseerr | 5002 | — | `⚠️ TCP-W :5002` | ja | Anfragen-UI |
| sonarr | 5003 | 5003 | `⚠️ TCP-W :5003` | ja | UID=5003 (skuid) |
| radarr | 5004 | 5004 | `⚠️ TCP-W :5004` | ja | UID=5004 (skuid) |
| readarr | 5005 | 5005 | `⚠️ TCP-W :5005` | ja | UID=5005 |
| prowlarr | 5006 | 5006 | `⚠️ TCP-W :5006` | ja | UID=5006 · VPN-NetNS |
| sabnzbd | 5007 | 5007 | `⚠️ TCP-W :5007` | ja | UID=5007 · VPN-NetNS |
| [audiobookshelf](../../modules/50-media/audiobookshelf.nix) | 5008 | — | `🔵 TCP-L :5008` | ja | Node.js |
| [navidrome](../../modules/50-media/navidrome.nix) | 5009 | — | `🔵 TCP-L :5009` | ja | Go · UDS möglich |
| [lidarr](../../modules/50-media/arr.nix) | 5010 | 5010 | `⚠️ TCP-W :5010` | ja | UID=5010 |

> **Servarr-Suite + Jellyfin** (.NET-Runtime): keine native Unix-Domain-Socket-Unterstützung —
> bleiben dauerhaft TCP. Wildcard-Binding ist durch VPN-Confinement und Firewall (Stufe ≥8) abgesichert.
> Siehe [ADR-004 — UDS-Konsequenzen](../adr/004-unix-socket-upstreams.md).

---

## 60-apps {#60-apps}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| [vaultwarden](../../modules/60-apps/61-core.nix) | 6001 | — | `🎯 UDS* /run/vaultwarden/vaultwarden.sock` | ja | Passwörter |
| homepage | 6002 | — | `🎯 UDS* /run/homepage/homepage.sock` | ja | Dashboard |
| [paperless](../../modules/60-apps/automation.nix) | 6003 | — | `🎯 UDS* /run/paperless/paperless.sock` | ja | Dokumente |
| filebrowser | 6005 | — | `🔵 TCP-L :6005` | ja | Go · UDS möglich |
| linkwarden | 6006 | — | `🎯 UDS* /run/linkwarden/linkwarden.sock` | ja | Bookmarks |
| [open-webui](../../modules/60-apps/61-core.nix) | 6007 | — | `🎯 UDS* /run/open-webui/open-webui.sock` | ja | LLM-Chat |

---

## 70-home-automation {#70-home-automation}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| [home-assistant](../../modules/70-home-automation/home-assistant.nix) | — | — | `🌐 ext :8123` | nein | LAN-Zugriff nötig |
| zigbee2mqtt | 1004 | — | `🔵 TCP-L :1004` | ja | IoT-Frontend |
| mosquitto | — | — | `🌐 ext :1883` | nein | MQTT-Broker, IANA |

---

## 70-forge {#70-forge}

| Service | ID | UID | Transport | SSO | Modul |
|---------|:--:|:---:|-----------|:---:|-------|
| amp | 7004 | — | `🔵 TCP-L :7004` | nein | Game-Server-Panel |

---

## Infrastruktur (kein Caddy) {#infrastruktur}

| Service | Transport | Besonderheit |
|---------|-----------|-------------|
| postgresql | `🟢 UDS /run/postgresql/.s.PGSQL.5432` | intern, kein Netz |
| valkey | `🟢 UDS /run/redis-valkey/valkey.sock` | RESP2, kein TCP |
| netbird-mgmt | `🌐 ext :8011` | WireGuard-Control-Plane |
| netbird-signal | `🌐 ext :8012` | STUN/TURN |
| ssh | `🌐 ext :2222` | Dropbear (Rescue), IANA |

---

## Socket-Migration — Offene Lücken {#socket-migration}

`server-map.nix` deklariert 8 Services als UDS — nur 2 sind live.
Die folgende Liste zeigt was fehlt und ob es technisch umsetzbar ist.

| Service | Geplanter Socket | Technisch? | Prio |
|---------|-----------------|-----------|------|
| pocket-id | `/run/pocket-id/pocket-id.sock` | Go — ja | hoch (OIDC-Provider) |
| gatus | `/run/gatus/gatus.sock` | Go — ja | mittel |
| vaultwarden | `/run/vaultwarden/vaultwarden.sock` | Rust/Rocket — ja | hoch (Passwörter) |
| homepage | `/run/homepage/homepage.sock` | Node.js — ja | niedrig |
| paperless | `/run/paperless/paperless.sock` | Python/granian — ja | mittel |
| linkwarden | `/run/linkwarden/linkwarden.sock` | Next.js — ja | niedrig |
| open-webui | `/run/open-webui/open-webui.sock` | Python — ja | niedrig |
| filebrowser | — (noch nicht geplant) | Go — ja | mittel |
| navidrome | — (noch nicht geplant) | Go — ja | mittel |

**Nicht möglich** (.NET ohne UDS-Support): Jellyfin, Sonarr, Radarr, Readarr, Prowlarr, Lidarr, Jellyseerr.

**Wildcard-Bindings fixbar ohne UDS** (auf `127.0.0.1` einschränken): Loki `:4002`, Pocket-ID `:1001`.

---

## Neuen Service einbinden {#neue-services}

1. **ID vergeben** — nächste freie Nummer im Layer-Block (`60xx`, `70xx`, …)
2. **Port registrieren** — `my.ports.<name>` in [`modules/00-core/01-core.nix`](../../modules/00-core/01-core.nix)
3. **UID anlegen** (falls eigener Systemuser) — [`lib/uid-registry.nix`](../../lib/uid-registry.nix)
4. **server-map.nix** — Eintrag mit `transport = "uds:…"` oder `"tcp:PORT"` ergänzen
5. **unix-sockets.nix** (bei UDS) — Socketpfad eintragen für `toCaddyUpstream`-Helper
6. **services-spec.nix** — `socket` oder `port` im Spec-Eintrag setzen (steuert Caddy-Routing)
7. **GUIDE-server-map.md** — diese Tabelle aktualisieren, Status setzen
8. ADR anlegen falls Architektur-Entscheidung nötig

---

## Debugging {#debugging}

```bash
# Alle gebundenen TCP-Ports anzeigen
ss -tlnp | grep -E '(100[0-9]|[4-7][0-9]{3})'

# Unix-Sockets prüfen — welche existieren wirklich
for s in grafana gatus pocket-id vaultwarden paperless linkwarden open-webui homepage; do
  sock=$(ls /run/$s/*.sock 2>/dev/null | head -1)
  [ -S "$sock" ] && echo "🟢 $s: $sock" || echo "❌ $s: kein Socket"
done

# Wildcard-Bindings aufdecken (Security-Check)
ss -tlnp | grep -v '127\.0\.0\.1\|::1' | grep LISTEN

# Caddy gegen UDS-Upstream testen
curl --unix-socket /run/grafana/grafana.sock http://localhost/api/health

# *arr UIDs prüfen (ADR-011)
id sonarr radarr readarr prowlarr sabnzbd lidarr
```

---

## Siehe auch {#siehe-auch}

- [ADR-011 — Unified Port=UID-Schema](../adr/011-unified-port-uid-schema.md) — Warum ID = Port = UID = Ordner-Präfix
- [ADR-004 — Unix-Socket-Upstreams](../adr/004-unix-socket-upstreams.md) — welche Services UDS vs. TCP und warum
- [ADR-008 — nftables L4-Härtung](../adr/008-nftables-l4-hardening.md) — `skuid`-Regeln die UIDs aus dieser Tabelle nutzen
- [`lib/server-map.nix`](../../lib/server-map.nix) — maschinenlesbare Quelle der Wahrheit
- [`lib/unix-sockets.nix`](../../lib/unix-sockets.nix) — Socket-Pfade für `toCaddyUpstream`-Helper
- [`lib/uid-registry.nix`](../../lib/uid-registry.nix) — UID/GID-Vergabe
