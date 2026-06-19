/*
  ---
  id: audiobookshelf
  upstream_repo: "advplyr/audiobookshelf"
  ---
*/

{
  config,
  lib,
  pkgs,
  ...
}:

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
        host = "127.0.0.1";
        user = "audiobookshelf";
        group = "audiobookshelf";
        openFirewall = false;
        package = pkgs.audiobookshelf.override { ffmpeg = pkgs.ffmpeg-full; };
      };

      # Allow audiobookshelf to read/write the media array AND use Intel QSV via iGPU
      users.users.audiobookshelf.extraGroups = [
        "media"
        "render"
        "video"
      ];

      # WebSockets are handled automatically by Caddy. We use native login (no SSO bypass required).
      services.caddy.virtualHosts."audiobookshelf.${domain}" = {
        extraConfig = caddy.proxy portABS;
      };

      systemd.services.audiobookshelf = {
        serviceConfig = {
          MemoryHigh = "2G";
          MemoryMax = "4G";
          OOMScoreAdjust = 100;

          # Additional Hardening
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          # Hardware Transcoding: Allow access to /dev/dri
          PrivateDevices = lib.mkForce false;
          DeviceAllow = [ "/dev/dri rw" ];
        };
      };
    })
  ];
}
