---
meta:
  role: doc
  purpose: ADR-5032 — Warum Sonarr/Radarr/Readarr (und Lidarr) bewusst off-VPN bleiben
  status: accepted
  date: 2026-07-11
  error_pattern: "sonarr.*privado|radarr.*VPN|readarr.*RestrictNetworkInterfaces"
  quick_fix: "Nur SABnzbd + Prowlarr in usenet-confinement — *arr-Managers brauchen kein VPN"
  services: [sonarr, radarr, readarr, lidarr, prowlarr, sabnzbd]
  betrifft:
    - modules/50-media/57-usenet-confinement/default.nix
    - modules/50-media/52-arr.nix
    - lib/nftables-rules.nix
  docs:
    - docs/adr/5031-usenet-vpn-sandbox.md
    - docs/adr/011-unified-port-uid-schema.md
    - docs/adr/2008-nftables-l4-hardening.md
    - docs/guides/GUIDE-media-stack.md
  tags:
    - adr
    - vpn
    - media
    - arr
    - security
---

# ADR-5032: *arr-Manager off-VPN (Sonarr/Radarr/Readarr/Lidarr) {#adr-5032}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-11 |
| **Host** | q958 |
| **Ergänzt** | [ADR-5031 — Usenet VPN-Sandbox](5031-usenet-vpn-sandbox.md) |

---

## Kontext {#kontext}

Nach [ADR-5031](5031-usenet-vpn-sandbox.md) laufen **SABnzbd** und **Prowlarr** in einer host-basierten VPN-Sandbox (`RestrictNetworkInterfaces`, nftables `skuid`-Guard, UID-Routing über `privado`).

Die Frage: müssen **Sonarr, Radarr, Readarr, Lidarr** ebenfalls durch das VPN?

Diese Dienste sind .NET-Manager: sie orchestrieren Downloads, importieren Dateien, sprechen LAN-APIs — sie laden **nicht selbst** über Usenet/Indexer aus dem Internet.

## Entscheidung {#entscheidung}

**Nur Usenet-Egress-Dienste (SABnzbd, Prowlarr) sind VPN-pflichtig. Sonarr, Radarr, Readarr und Lidarr bleiben bewusst off-VPN auf dem Host.**

| Service | UID | VPN-Sandbox? | Egress-Typ | Begründung |
|---------|-----|--------------|------------|------------|
| SABnzbd | 5007 | ✅ ja | Usenet (NNTP) | ISP-sensitiver Traffic, Kill-Switch |
| Prowlarr | 5006 | ✅ ja | Indexer-HTTP | Tracker/Indexer-Abfragen, Leak-Risiko |
| Sonarr | 5003 | ❌ nein | LAN/API only | Spricht SABnzbd lokal; kein WAN-Usenet |
| Radarr | 5004 | ❌ nein | LAN/API only | wie Sonarr |
| Readarr | 5005 | ❌ nein | LAN/API only | wie Sonarr |
| Lidarr | 5010 | ❌ nein | LAN/API only | wie Sonarr |

### Schutzschichten für off-VPN-*arr {#schutz-off-vpn}

1. **Bind localhost** — alle *arr lauschen auf `127.0.0.1:50xx` ([ADR-011](011-unified-port-uid-schema.md))
2. **nftables input** — `skuidArrGuard` erlaubt neue Verbindungen auf Sonarr/Radarr/Readarr-Ports nur von LAN + Tailscale (`100.64.0.0/10`), nicht vom WAN
3. **Caddy SSO** — externer Zugriff nur über `forward_auth` (Pocket-ID)
4. **Kein Usenet-Egress** — Prozesse der UIDs 5003–5005/5010 haben keinen geschäftsmäßigen Grund, `privado` zu nutzen

### Datenfluss {#datenfluss}

```
Browser → Caddy (SSO) → Sonarr:5003 (localhost)
                              ↓ API (localhost)
                         SABnzbd:5007 (UID 5007, nur privado+lo)
                              ↓ NNTP
                         Usenet (über VPN)
```

Prowlarr (VPN) versorgt Indexer; Sonarr/Radarr/Readarr konsumieren nur die lokale SABnzbd-Queue und Dateisystem-Pfade (`/data/downloads`, `/data/media`).

## Diagnose {#diagnose}

**Symptom:** Diskussion „alle *arr sollten ins VPN“ oder Konfig-Vorschlag mit `RestrictNetworkInterfaces` auf Sonarr.

```bash
# VPN-Sandbox nur auf Usenet-Egress? {#vpn-sandbox-nur-usenet}
systemctl show sabnzbd prowlarr -p RestrictNetworkInterfaces,BindsTo
systemctl show sonarr radarr readarr -p RestrictNetworkInterfaces,BindsTo

# *arr lauschen localhost? {#arr-localhost}
ss -tlnp | grep -E '500[345]|5010'

# nftables LAN-only für *arr-Ports {#nftables-arr}
nft list ruleset | grep "arr LAN"
```

**Erwartung:**

| Unit | RestrictNetworkInterfaces | BindsTo privado |
|------|---------------------------|-----------------|
| sabnzbd, prowlarr | `lo privado` | ja |
| sonarr, radarr, readarr, lidarr | *(nicht gesetzt)* | nein |

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Weniger Komplexität: kein NetNS, kein Split-DNS für .NET-Apps
- Stabiler LAN-Import: Hardlinks/Atomic-Moves auf `/data/*` ohne NS-Bridges
- QSV/GPU-Gruppen (`video`, `render`) ohne VPN-NS-Konflikte
- Klare Threat-Model-Trennung: **Egress-Schutz** (VPN) vs. **Input-Schutz** (nftables + SSO)

### Negativ / Trade-offs {#negativ}

- Sonarr/Radarr-*Prozess* könnte theoretisch WAN erreichen (kein BPF-Interface-Lock). Mitigation: nftables `skuidArrGuard` + localhost-Bind + kein Forward-Proxy in den Apps
- Ein kompromittierter *arr-Prozess hat LAN-Zugriff — akzeptabel im Homelab-Threat-Model (kein adversarial Multi-Tenant)

## Alternativen verworfen {#alternativen}

| Alternative | Warum verworfen |
|-------------|-----------------|
| Alle *arr in VPN/NetNS (nixflix/nixarr) | Overhead, bricht deklarative Pfade, kein Usenet-Egress-Gewinn |
| Sonarr auch `RestrictNetworkInterfaces` | Blockiert LAN-API zu SABnzbd auf localhost — funktioniert, aber löst kein Problem |
| Nur nftables ohne VPN für SAB | Unzureichend — NNTP-Egress braucht Routing-Level-Kill-Switch ([ADR-5031](5031-usenet-vpn-sandbox.md)) |

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-11 | Initial — explizite Abgrenzung zu ADR-5031 |

## Siehe auch {#siehe-auch}

- [ADR-5031 — Usenet VPN-Sandbox](5031-usenet-vpn-sandbox.md)
- [ADR-011 — Port=UID-Schema](011-unified-port-uid-schema.md)
- [GUIDE-media-stack](../guides/GUIDE-media-stack.md)
- [GUIDE-nftables-hardening](../guides/GUIDE-nftables-hardening.md) — skuid-Segmentierung