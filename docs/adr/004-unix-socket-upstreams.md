---
meta:
  role: doc
  purpose: ADR-004 Unix-Socket-Upstreams für Caddy
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - caddy
---

# ADR-004: Unix-Socket-Upstreams für interne Dienste

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext

- TCP-Ports auf `127.0.0.1` sind einfach, aber jeder Dienst braucht eine Port-Nummer und `ss`-Sichtbarkeit.
- Valkey, Forgejo und Grafana sollen ohne zusätzliche TCP-Listener an Caddy angebunden werden.
- Pfade müssen zentral dokumentiert sein, damit Module nicht eigene Socket-Pfade erfinden.

## Entscheidung

1. **Eine Wahrheit:** `lib/unix-sockets.nix` — Pfade + `toCaddyUpstream`.
2. **Caddy-Helfer:** `lib/caddy-helpers.nix` → `proxyUnixSso`, `proxyUnixDirect`, …
3. **Kein Socket** ohne Eintrag in `unix-sockets.nix` — neue Dienste erweitern die Lib zuerst.

## Konsequenzen

### Positiv

- Weniger Port-Kollisionen; klarere Grenze Ingress ↔ App.
- `mkService` in `service-factory.nix` unterstützt `socketPath` als Alternative zu `port`.

### Negativ

- Socket-Berechtigungen (Gruppe `caddy`, `redis`) müssen pro Dienst stimmen.
- Debugging mit `curl` schwieriger als bei TCP — `socat` oder Unit-Logs nutzen.

### Implementierung

| Artefakt | Pfad |
|----------|------|
| Socket-SSOT | `lib/unix-sockets.nix` |
| Caddy | `lib/caddy-helpers.nix` |
| Registry | `NIXH-05-LIB-005` in `docs/SPEC_REGISTRY.md` |