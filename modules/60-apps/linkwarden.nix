{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgLinkwarden = config.my.services.linkwarden;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgLinkwarden.enable {
    services.linkwarden = {
      enable = true;
      inherit (cfgLinkwarden) port;
      environmentFile = "/home/moritz/secrets/linkwarden.env";
      environment = {
        NEXTAUTH_URL = "https://links.${domain}/api/v1/auth";
        HOST = "127.0.0.1";
      };
    };

    services.caddy.virtualHosts."links.${domain}" = {
      extraConfig = caddy.proxySso cfgLinkwarden.port;
    };

    systemd.services.linkwarden = {
      serviceConfig = {
        OOMScoreAdjust = 500;
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        StateDirectory = "linkwarden";
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        ProtectClock = true;
        ProtectHostname = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };
    };
  };
}

