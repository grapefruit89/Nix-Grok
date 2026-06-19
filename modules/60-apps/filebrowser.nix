/*
  ---
  id: filebrowser
  upstream_repo: "filebrowser/filebrowser"
  ---
*/

{
  config,
  lib,
  ...
}:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgFilebrowser = config.my.services.filebrowser;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgFilebrowser.enable {
    services.filebrowser = {
      enable = true;
      settings = {
        inherit (cfgFilebrowser) port;
        address = "127.0.0.1";
        root = cfgFilebrowser.rootPath;
        database = cfgFilebrowser.databasePath;
      };
    };

    services.caddy.virtualHosts."files.${domain}" = {
      extraConfig = caddy.proxySso cfgFilebrowser.port;
    };

    systemd.tmpfiles.rules = [
      "d /data/state/filebrowser 0750 filebrowser filebrowser -"
    ];

    systemd.services.filebrowser.serviceConfig = {
      OOMScoreAdjust = 300;
      ReadWritePaths = [ (builtins.dirOf cfgFilebrowser.databasePath) ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      RestrictNamespaces = true;
      ProtectClock = true;
      ProtectHostname = true;
      LockPersonality = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };
}
