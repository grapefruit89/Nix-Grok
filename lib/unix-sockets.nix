# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: UDS-Pfad-Registry (SSoT) — services-spec, server-map und Module importieren hier
#   docs:
#     - docs/adr/1004-unix-socket-upstreams.md
#     - docs/adr/1019-uds-first-philosophy.md
#     - docs/adr/011-unified-port-uid-schema.md
#     - docs/guides/GUIDE-server-map.md
#   tags:
#     - unix-socket
#     - caddy
# ---
{ lib, ... }:
let
  paths = {
    valkey = "/run/redis-valkey/valkey.sock";
    grafana = "/run/grafana/grafana.sock";
    secrets-portal = "/run/secrets-portal/secrets-portal.sock";
    postgresql = "/run/postgresql/.s.PGSQL.5432";
  };

  # services-spec-Einträge mit socket-Feld — Drift-Assertion gegen diese Map
  specSockets = {
    inherit (paths) postgresql valkey grafana;
    secrets-portal = paths.secrets-portal;
  };

  socketDriftAssertion =
    spec: registry:
    let
      offenders = lib.filter (
        name:
        let
          entry = spec.${name} or { };
          expected = registry.${name};
        in
        (entry.socket or null) != expected
      ) (lib.attrNames registry);
    in
    {
      assertion = offenders == [ ];
      message = "[SOCKET-REGISTRY] my.services.spec socket weicht von lib/unix-sockets.nix ab: ${lib.concatStringsSep ", " offenders}";
    };
in
paths
// {
  inherit paths specSockets socketDriftAssertion;

  toCaddyUpstream = path: "unix/${lib.removePrefix "/" path}";
  toTransport = path: "uds:${path}";
}
