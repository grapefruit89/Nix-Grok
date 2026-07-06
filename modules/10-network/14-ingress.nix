# ---
# meta:
#   id: NIXH-10-ING-001
#   layer: 3
#   role: module
#   purpose: Spez-basierter Caddy-Ingress — einzige Quelle für vHosts
#   lib:
#     - lib/caddy-ingress.nix
#     - lib/service-enable.nix
#   tags:
#     - caddy
#     - ingress
# ---
{
  config,
  lib,
  ...
}:
let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  ingressLib = import ../../lib/caddy-ingress.nix { inherit lib caddy; };
  enableMap = import ../../lib/service-enable.nix { inherit lib; };

  domain = config.my.configs.identity.domain;
in
{
  options.my.ingress = {
    fromSpec = {
      enable = lib.mkEnableOption "Caddy vHosts aus my.services.spec (implizit mit Caddy)";
    };
  };

  config = {
    my.ingress.fromSpec.enable = lib.mkDefault config.services.caddy.enable;
  }
  // lib.mkIf (config.services.caddy.enable && config.my.ingress.fromSpec.enable) {
    services.caddy.virtualHosts =
      let
        vHosts = ingressLib.genVirtualHosts {
          spec = config.my.services.spec;
          inherit domain;
          isEnabled = enableMap.enabled config;
        };
      in
      if config.my.security.acme.enable then
        lib.mapAttrs (_: vhost: vhost // { useACMEHost = domain; }) vHosts
      else
        vHosts;
  };
}
