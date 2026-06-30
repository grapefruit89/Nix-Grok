---
meta:
  role: doc
  purpose: Entscheidung für Unix-Domain-Sockets als primäres IPC-Protokoll zwischen Caddy und Backend-Diensten
  tags:
    - unix-socket
    - caddy
    - architecture
    - security
---

# ADR-019: Unix-Domain-Sockets First

**Status:** Accepted  
**Datum:** 2026-06-30  
**Kontext:** UDS-Migration (Vaultwarden), Bereinigung von server-map.nix, services-spec.nix

---

## Kontext

Das System nutzte historisch TCP-Localhost-Verbindungen (`127.0.0.1:PORT`) für den Caddy→Service-Hop. Caddy als Reverse-Proxy kommuniziert dabei mit Backend-Diensten auf demselben Host — ein Fall, bei dem Unix Domain Sockets (UDS) klarer besser geeignet sind.

Gleichzeitig hatten `server-map.nix` und `unix-sockets.nix` mehrere Dienste aspirational als UDS deklariert, obwohl die eigentlichen Konfigurationen (`services-spec.nix`, Modulcode) noch TCP verwendeten. Dieser inkonsistente Zustand wurde in dieser Session bereinigt.

---

## Entscheidung

**Principle: UDS-First für alle Caddy-frontierten Dienste, die das technisch unterstützen.**

Der Caddy→Service-Hop nutzt immer dann Unix Domain Sockets, wenn:
1. Die Applikation einen Socket-Listener unterstützt, **und**
2. Das NixOS-Modul diese Option exponiert oder konfigurierbar macht.

Dienste, die TCP bleiben, sind die Minderheit und müssen einen konkreten Grund haben.

---

## Begründung

### Warum UDS statt TCP-Localhost?

| Aspekt | TCP 127.0.0.1 | Unix Domain Socket |
|--------|--------------|-------------------|
| Angriffsfläche | TCP-Stack, Port sichtbar | Nur Dateisystem |
| Zugriffssteuerung | Jeder Prozess auf loopback | Filesystem-ACL (Eigentümer/Gruppe) |
| Overhead | TCP-Handshake, Checksums | Kernel-Bypass |
| Portkonflikt-Risiko | Port muss frei sein | Pfad ist eindeutig |
| Sichtbarkeit (`ss -tlnp`) | Port taucht auf | Socket nicht |

Der Schlüsselvorteil: **Nur der Caddy-Prozess** (über Gruppenmitgliedschaft) kann den Socket erreichen. Kein anderer lokaler Prozess kann sich verbinden, selbst wenn er kompromittiert ist.

### Warum socket-Eintrag in services-spec als SSoT?

`services-spec.nix` ist die Single Source of Truth für Caddy. Wenn dort `socket:` steht, nutzt `mkUpstream` automatisch `unix/path/to/socket`. Sonstige Dateien (`server-map.nix`, `unix-sockets.nix`) müssen damit übereinstimmen — nicht umgekehrt.

---

## Implementierte UDS-Dienste (Stand 2026-06-30)

| Dienst | Socket-Pfad | Methode |
|--------|-------------|---------|
| Grafana | `/run/grafana/grafana.sock` | `settings.server.protocol = "socket"` |
| Valkey | `/run/redis-valkey/valkey.sock` | `services.redis.unixSocket` |
| PostgreSQL | `/run/postgresql/.s.PGSQL.5432` | Standard PostgreSQL |
| Vaultwarden | `/run/vaultwarden/vaultwarden.sock` | `ROCKET_ADDRESS = "unix:/run/..."` |

---

## Dienste die TCP bleiben — und warum

| Dienst | Grund |
|--------|-------|
| Loki | Clients (Vector, Grafana) sprechen kein `http+unix://` zuverlässig |
| Pocket-ID | NixOS-Modul hat keine socket-Option |
| Gatus | `services.gatus.settings.web.address` ist ein IP-String, kein Pfad |
| Homepage | Node.js `listenPort` ohne Socket-Unterstützung |
| Linkwarden | Next.js TCP |
| Open-WebUI | FastAPI/uvicorn via NixOS-Modul ohne UDS-Pfad |
| Paperless | Gunicorn kann UDS, NixOS-Modul nicht konfiguriert — **zukünftiger Kandidat** |
| Semaphore | Go HTTP-Server, TCP |
| Arr-Stack | .NET-Framework, kein UDS |
| Jellyfin/ABS | .NET/Node, kein UDS |
| Navidrome | Go HTTP, kein UDS via Modul |
| Scrutiny | Go HTTP, kein UDS |

---

## Konsequenzen

### Positiv
- Sicherheitsmodell: Caddy→Service-Kanal ist filesystem-ACL-gesichert
- Keine unbenutzten TCP-Ports auf loopback
- Klarer SSoT: `services-spec.nix` entscheidet, `server-map.nix` dokumentiert Realität

### Negativ / Einschränkungen
- Dienste mit UDS benötigen `RuntimeDirectory` + Gruppe für Caddy
- `genVaultwardenVhost` (und ähnliche spezielle Vhost-Generatoren) müssen bei UDS-Migration refaktoriert werden — sie akzeptierten vorher `port:int`, jetzt `upstream:string`

### Wartungshinweis
Wenn ein neuer Dienst hinzukommt:
1. Prüfe in der NixOS-Modul-Dokumentation, ob UDS konfigurierbar ist
2. Füge in `unix-sockets.nix` den Pfad hinzu
3. Setze `socket:` statt `port:` in `services-spec.nix`
4. Trage `uds:PATH` in `server-map.nix` ein
5. Füge Caddy zur Dienst-Gruppe hinzu (`users.users.caddy.extraGroups`)

---

## Verwandte ADRs

- ADR-004: Unix Socket Upstreams (erstes UDS-Konzept)
- ADR-011: Unified Port/UID-Schema (Ports bleiben für TCP-Dienste als ID)
- ADR-017: Caddy Health Checks
