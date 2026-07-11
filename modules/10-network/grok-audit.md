# Audit: modules/10-network
Datum: 2026-07-11
Auditor: Grok (Drift-Prevention + Cleanup-Pass)

## Übersicht

Netzwerk-/Ingress-Schicht mit zentraler SSoT, Isomorphie (ADR-011) und Build-Zeit-Drift-Assertions.

**Drift-Schutz:**
- `lib/unix-sockets.nix` — UDS-Pfad-Registry + `socketDriftAssertion`
- `lib/blocky-allowlist.nix` — `{file, tmpfilesRule}` atomar
- `my.network.protocol.{dns,dot}` — IANA-Ports
- `my.network.routing.privadoTableName` — systemd-networkd routeTables/Routes/Rules

**Cleanup (2026-07-11):**
- `StartLimit*` auf Unit-Ebene (`1002-blocky`, `1095-databases`) — nicht in `serviceConfig`
- `services.blocky.enableConfigCheck = true` — Build-Time YAML-Validierung
- `dns-guard`: Timer entfernt → event-getrieben (Boot, path units, Secrets-Provision)
- `privado.dns` dokumentiert: nur Usenet-Sandbox, nicht networkd `[Network] DNS=`
- `meta/index.yaml` + Docs auf Isomorphie-Pfade aktualisiert

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| Port-SSoT | ✓ | `my.ports.*` |
| Socket-SSoT | ✓ | `lib/unix-sockets.nix` |
| Protokoll-Ports | ✓ | `my.network.protocol` |
| Machine-Werte | ✓ | DDNS/Privado/Allowlist aus Profil |
| VPN Routing | ✓ | networkd deklarativ |
| Event-Trigger | ✓ | dns-guard path units; kein periodischer Timer in 10-network |
| systemd Unit-Keys | ✓ | `startLimit*` korrekt platziert |

---

## Verbleibende bewusste Konstanten

- Cloudflare-CIDRs in Caddy (`1090-host-network.nix`) — Vendor-Daten
- WireGuard `0.0.0.0/0`, `PersistentKeepalive = 25` — Protokoll-Semantik
- DB-Tuning in `1095-databases.nix` — Betriebsparameter
- `dns-guard` Shell — externer Cloudflare-API-Zustand (OK per Runtime-Regel)