# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Standard-UDS-Pfade und Caddy-Upstream-Konvertierung
#   docs:
#     - docs/adr/004-unix-socket-upstreams.md
#     - docs/adr/011-unified-port-uid-schema.md
#     - docs/guides/GUIDE-server-map.md
#   tags:
#     - unix-socket
#     - caddy
# ---
{ lib, ... }:
{
  # ── bereits aktiv ──────────────────────────────────────────────────────────
  valkey = "/run/redis-valkey/valkey.sock";
  grafana = "/run/grafana/grafana.sock";

  # ── 10-network ─────────────────────────────────────────────────────────────
  pocket-id = "/run/pocket-id/pocket-id.sock";

  # ── 40-observability ───────────────────────────────────────────────────────
  gatus = "/run/gatus/gatus.sock";

  # ── 50-media ───────────────────────────────────────────────────────────────
  # Servarr (.NET) und Jellyfin nutzen TCP localhost — keine nativen UDS

  # ── 60-apps ────────────────────────────────────────────────────────────────
  vaultwarden = "/run/vaultwarden/vaultwarden.sock";
  paperless = "/run/paperless/paperless.sock";
  linkwarden = "/run/linkwarden/linkwarden.sock";
  open-webui = "/run/open-webui/open-webui.sock";
  homepage = "/run/homepage/homepage.sock";

  # ── 70-forge ───────────────────────────────────────────────────────────────

  # ── helper ─────────────────────────────────────────────────────────────────
  toCaddyUpstream = path: "unix/${lib.removePrefix "/" path}";
}
