/*
  ---
  id: navidrome
  upstream_repo: "navidrome/navidrome"
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
  cfg = config.my.services.navidrome;
  domain = config.my.configs.identity.domain;
  portNavidrome = config.my.ports.navidrome;

in
{
  config = lib.mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        Port = portNavidrome;
        Address = "127.0.0.1";
        MusicFolder = "/data/media/music";
        DataFolder = "/var/lib/navidrome";
        LogLevel = "info";
      };
    };

    # Give navidrome access to the media folder
    users.users.navidrome.extraGroups = [ "media" ];

    services.caddy.virtualHosts."navidrome.${domain}" = {
      extraConfig = caddy.proxy portNavidrome;
    };
  };
}
