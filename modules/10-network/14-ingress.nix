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
  vpnConnLib = import ../../lib/vpn-connection.nix { inherit lib; };
  ingressLib = import ../../lib/caddy-ingress.nix {
    inherit lib caddy;
    vpnConn = {
      cfg = config.my.services.vpn-confinement;
      inherit (vpnConnLib) connectionAddress;
    };
  };
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
    services.caddy.virtualHosts = ingressLib.genVirtualHosts {
      spec = config.my.services.spec;
      inherit domain;
      isEnabled = enableMap.enabled config;
      blockyMetricsPort = config.my.services.blocky.metricsPort or 4000;
    };
  };
}
