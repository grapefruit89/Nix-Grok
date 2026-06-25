# ---
# meta:
#   id: NIXH-60-APP-TPL
#   layer: 3
#   role: module
#   purpose: Onboarding-Vorlage für neue Apps — Kopieren, anpassen, in default.nix importieren
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/adr/README.md
#   lib:
#     - lib/service-factory.nix
#     - lib/dns-map.nix
#   tags:
#     - template
#     - onboarding
# ---
{ config, lib, pkgs, ... }:

let
  # 1) Service-Name = dns-map-Schlüssel (oder eigenen host setzen)
  serviceName = "example-app";
  factory = import ../../lib/service-factory.nix { inherit lib; };
  # port = config.my.ports.${serviceName};
in
{
  # 2) Enable-Option gehört in modules/*/default.nix — NICHT hier .enable setzen
  # 3) Rollout: machines/<host>/rollout.nix ist die einzige .enable-Quelle

  # options.my.services.<serviceName>.enable in modules/*/default.nix deklarieren
  config = lib.mkIf false (lib.mkMerge [
    {
      # NixOS-Dienst aktivieren
      # services.${serviceName} = { enable = true; ... };
    }

    # Fabrik: Caddy vHost aus dns-map + systemd-Hardening
    (factory.mkService {
      inherit config;
      name = serviceName;
      port = 8080; # config.my.ports.${serviceName}
      mode = "sso"; # sso | tailscale-sso | streaming | security | direct
      readWritePaths = [ "/var/lib/${serviceName}" ];
      # host = "custom.${config.my.configs.identity.domain}"; # optional Override
    })
  ]);
}