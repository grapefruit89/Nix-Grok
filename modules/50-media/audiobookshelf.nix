{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgABS = config.my.services.audiobookshelf;
  domain = config.my.configs.identity.domain;
  portABS = config.my.ports.audiobookshelf;

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgABS.enable {
      services.audiobookshelf = {
        enable = true;
        port = portABS;
        user = "audiobookshelf";
        group = "audiobookshelf";
        openFirewall = false;
        # Note: We use the default ffmpeg as approved.
      };

      # Allow audiobookshelf to read/write the media array
      users.users.audiobookshelf.extraGroups = [ "media" ];

      # WebSockets are handled automatically by Caddy. We use native login (no SSO bypass required).
      services.caddy.virtualHosts."audiobookshelf.${domain}" = {
        extraConfig = caddy.proxy portABS;
      };

      systemd.services.audiobookshelf = {
        serviceConfig = {
          # Additional Hardening
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
        };
      };
    })
  ];
}
