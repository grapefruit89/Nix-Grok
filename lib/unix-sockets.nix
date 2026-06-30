# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Standard-UDS-Pfade und Caddy-Upstream-Konvertierung
#   docs:
#     - docs/adr/004-unix-socket-upstreams.md
#     - docs/adr/019-uds-first-philosophy.md
#     - docs/adr/011-unified-port-uid-schema.md
#     - docs/guides/GUIDE-server-map.md
#   tags:
#     - unix-socket
#     - caddy
# ---
{ lib, ... }:
{
  # ── aktiv & implementiert ──────────────────────────────────────────────────
  valkey = "/run/redis-valkey/valkey.sock";
  grafana = "/run/grafana/grafana.sock";

  # ── PostgreSQL (Standard-Socket, immer aktiv) ──────────────────────────────
  postgresql = "/run/postgresql/.s.PGSQL.5432";

  # ── TCP-Dienste (kein UDS möglich oder noch nicht migriert) ───────────────
  # pocket-id    — NixOS-Modul hat keine socket-Option            → tcp:1001
  # gatus        — web.address/port Konfiguration, kein UDS       → tcp:4003
  # loki         — Vector/Grafana-Client ohne http+unix Support   → tcp:4002
  # homepage     — Node.js listenPort                             → tcp:6002
  # paperless    — Gunicorn (Django), UDS möglich, ausstehend     → tcp:6003
  # linkwarden   — Next.js                                        → tcp:6006
  # open-webui   — FastAPI/uvicorn, kein UDS via NixOS-Modul      → tcp:6007
  # semaphore    — Go HTTP-Server                                 → tcp:7002

  # ── helper ─────────────────────────────────────────────────────────────────
  toCaddyUpstream = path: "unix/${lib.removePrefix "/" path}";
}
