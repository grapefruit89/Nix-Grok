# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Standard-UDS-Pfade und Caddy-Upstream-Konvertierung
#   tags:
#     - unix-socket
#     - caddy
# ---
{ lib, ... }:

{
  valkey = "/run/redis-valkey/valkey.sock";
  forgejo = "/run/forgejo/forgejo.sock";
  grafana = "/run/grafana/grafana.sock";

  toCaddyUpstream = path: "unix/${lib.removePrefix "/" path}";
}
