---
meta:
  role: doc
  purpose: ADR-5033 — On-demand HTTP via systemd socket-proxyd (statt Sablier)
  status: accepted
  date: 2026-07-11
  error_pattern: "shiori.*inactive|socket-proxyd|Connection refused.*6006"
  quick_fix: "systemctl status shiori.socket shiori.service; curl http://127.0.0.1:6006 weckt Backend"
  services: [shiori, libreseerr, filebrowser, open-webui]
  betrifft:
    - lib/on-demand-http.nix
    - modules/60-apps/63-on-demand-apps.nix
    - modules/90-policy/92-on-demand.nix
  docs:
    - docs/adr/7005-cloudflare-dns-acme-ddns.md
    - docs/guides/ANTIPATTERNS.md
    - lib/forbidden-tech.nix
  tags:
    - adr
    - systemd
    - on-demand
    - socket-activation
    - ram
---

# ADR-5033: On-demand HTTP (systemd socket-proxyd) {#adr-5033}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-11 |
| **Host** | q958 |
| **Policy** | `my.policy.onDemand.enable` (Rollout ab Stufe 7) |

---

## Kontext {#kontext}

Selten genutzte Web-Apps (Lesezeichen, Dateibrowser, KI-UI) laufen sonst dauerhaft und belegen RAM — obwohl Zugriff sporadisch ist.

**Sablier** (Caddy-Plugin + Container-Runtime) ist verboten ([POL-CADDY-007](../lib/forbidden-tech.nix), [ADR-7005](7005-cloudflare-dns-acme-ddns.md)): No-Docker-Policy, kein zweites Orchestrierungs-Modell.

**SSH socket activation** ist ebenfalls verboten ([ANTIPATTERNS](../guides/ANTIPATTERNS.md#socket-activation-ssh)) — Aussperr-Risiko überwiegt RAM-Gewinn.

Für **unkritische HTTP-Backends** ist systemd-native Socket-Aktivierung akzeptabel.

## Entscheidung {#entscheidung}

**Zwei-Stufen-Modell mit `systemd-socket-proxyd`:**

**Wichtig:** `systemd-socket-proxyd` nutzt `sd_listen_fds()` — **kein** `StandardInput=socket` am Proxy setzen.

1. **Public socket** (`${name}.socket`) — lauscht auf `127.0.0.1:<publicPort>` (unverändert für Caddy/Gatus)
2. **Proxy** (`${name}.service`) — socket-aktiviert, `systemd-socket-proxyd 127.0.0.1:<internalPort>`
3. **Backend socket** (`${name}-backend.socket`) — lauscht auf `127.0.0.1:<internalPort>`
4. **Backend** (`${name}-backend.service`) — eigentliche App, startet bei erstem Connect

**Port-Konvention:** `internalPort = publicPort + 10000` (z.B. Shiori 6006 → Backend 16006).

Caddy-`reverse_proxy` bleibt auf dem Public-Port — **keine Caddy-Änderung**.

### Implementierte Dienste (Stufe 7+) {#dienste}

| Service | Public | Backend | Warum geeignet |
|---------|--------|---------|----------------|
| Shiori | 6006 | 16006 | Lesezeichen sporadisch |
| Filebrowser | 6005 | 16005 | Dateizugriff on-demand |
| Open WebUI | 6007 | 16007 | KI-UI nur bei Bedarf |
| Libreseerr | 6010 | 16010 | Buch-Anfragen selten |

### Bewusst **nicht** on-demand {#nicht-on-demand}

| Service | Warum nicht |
|---------|-------------|
| Sonarr/Radarr/Readarr/Prowlarr | Hintergrund-Tasks, API-Polling untereinander |
| Jellyfin | Streaming, Clients erwarten niedrige Latenz |
| Vaultwarden | Passwort-Manager — always-on |
| SABnzbd | Dauer-Downloads |
| SSH | ANTIPATTERN — Aussperr-Risiko |

## Architektur {#architektur}

```
Caddy → 127.0.0.1:6006 (shiori.socket)
           ↓ sd_listen_fds (fd 3+)
        shiori.service (ExecStartPre: start backend + wait)
           ↓ systemd-socket-proxyd
        127.0.0.1:16006 (shiori-backend bind)
           ↓
        shiori-backend.service
```

Nach erstem Request bleibt das Backend aktiv (kein Idle-Kill). Gewinn: **kein RAM/CPU bei Boot** und nach Reboot bis zur ersten Nutzung.

## Diagnose {#diagnose}

```bash
# Sockets lauschen, Backend schläft? {#sockets-lauschen}
systemctl is-active shiori.socket shiori-backend.socket
systemctl is-active shiori-backend.service   # → inactive (vor erstem Zugriff)

# Wecken {#wecken}
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:6006/
systemctl is-active shiori-backend.service   # → active

# Proxy-Logs {#proxy-logs}
journalctl -u shiori -u shiori-backend -n 20 --no-pager
```

## Fix {#fix}

```bash
# Socket hängt? {#socket-haengt}
systemctl restart shiori.socket shiori-backend.socket

# Backend startet nicht {#backend-startet-nicht}
journalctl -u shiori-backend -n 30 --no-pager
systemctl cat shiori-backend.service
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Rein systemd-native — kein Docker, kein Sablier, kein Caddy-Plugin
- Caddy/Gatus/Homepage-Ports unverändert ([ADR-011](011-unified-port-uid-schema.md))
- Erster Request hat Cold-Start-Latenz (~1–5 s) — akzeptabel für seltene Apps

### Negativ {#negativ}

- Backend bleibt nach Wake aktiv (kein automatisches Sleep) — ausreichend für Homelab-RAM-Ziel
- Doppelte systemd-Units pro Dienst — mehr Wartungsfläche
- Gatus-Healthchecks wecken Dienste periodisch — akzeptabler Trade-off

## Alternativen verworfen {#alternativen}

| Alternative | Warum verworfen |
|-------------|-----------------|
| Sablier | Container-Runtime, POL-CADDY-007 |
| Docker pause/unpause | POL-FT-001 No-Docker |
| SSH socket activation | ANTIPATTERN ADR-012 |
| Caddy `lb_on_demand` | Braucht Plugin/Infrastruktur außerhalb Policy |

## Artefakte {#artefakte}

| Pfad | Rolle |
|------|-------|
| `lib/on-demand-http.nix` | `mkProxy`, `mkBackendSocket`, Port-Offset |
| `modules/90-policy/92-on-demand.nix` | `my.policy.onDemand.enable` |
| `modules/60-apps/63-on-demand-apps.nix` | Vier Apps verdrahtet |

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-11 | Initial — Shiori, Filebrowser, Open WebUI, Libreseerr |

## Siehe auch {#siehe-auch}

- [ADR-7005 — Caddy-Plugin-Ersatz](7005-cloudflare-dns-acme-ddns.md)
- [ADR-5032 — *arr off-VPN](5032-arr-off-vpn.md)
- [ANTIPATTERNS — SSH socket activation](../guides/ANTIPATTERNS.md#socket-activation-ssh)