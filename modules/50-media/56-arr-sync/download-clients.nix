{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgSync = config.my.media.sync.downloadClients;
  cfgSabnzbd = config.my.services.sabnzbd;
  ports = config.my.ports;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };

  sabHost = "127.0.0.1";
  sabPort = ports.sabnzbd;
  hostBridgeAddr = "127.0.0.1";

  arrTargets = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = config.my.services.sonarr.enable;
      port = ports.sonarr;
      apiVersion = "v3";
      category = cfgSync.sonarr.category;
    };
    radarr = {
      enabled = config.my.services.radarr.enable;
      port = ports.radarr;
      apiVersion = "v3";
      category = cfgSync.radarr.category;
    };
    readarr = {
      enabled = config.my.services.readarr.enable;
      port = ports.readarr;
      apiVersion = "v1";
      category = cfgSync.readarr.category;
    };
    lidarr = {
      enabled = config.my.services.lidarr.enable;
      port = ports.lidarr;
      apiVersion = "v1";
      category = cfgSync.lidarr.category;
    };
  };

  targetsJson = builtins.toJSON (
    lib.mapAttrsToList (name: t: {
      inherit name;
      inherit (t) port;
      inherit (t) apiVersion;
      inherit (t) category;
      apiKeyFile = "/var/lib/secrets/${name}_api_key";
    }) arrTargets
  );

in
{
  options.my.media.sync.downloadClients = {
    enable = lib.mkEnableOption "Deklarative SABnzbd-Download-Client-Registrierung in *Arr-Services";

    sonarr.category = lib.mkOption {
      type = lib.types.str;
      default = "tv";
      description = "SABnzbd-Kategorie für Sonarr-Downloads.";
    };
    radarr.category = lib.mkOption {
      type = lib.types.str;
      default = "movies";
      description = "SABnzbd-Kategorie für Radarr-Downloads.";
    };
    readarr.category = lib.mkOption {
      type = lib.types.str;
      default = "audiobooks";
      description = "SABnzbd-Kategorie für Readarr-Downloads.";
    };
    lidarr.category = lib.mkOption {
      type = lib.types.str;
      default = "music";
      description = "SABnzbd-Kategorie für Lidarr-Downloads.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfgSabnzbd.enable && arrTargets != { }) {
      my.media.sync.downloadClients.enable = lib.mkDefault true;
    })
    (lib.mkIf (cfgSabnzbd.enable && cfgSync.enable && arrTargets != { }) {
      systemd.services.arr-sync-download-clients = {
        description = "Declarative SABnzbd Download-Client Registration in *Arr";
        after = [ "sabnzbd.service" ] ++ lib.mapAttrsToList (name: _: "${name}.service") arrTargets;
        wants = [ "sabnzbd.service" ];
        wantedBy = [ "multi-user.target" ];

        startLimitIntervalSec = 300;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 3;
        };

        environment = {
          SAB_HOST = sabHost;
          SAB_PORT = toString sabPort;
          SAB_KEY_FILE = "/var/lib/secrets/sabnzbd_api_key";
          HOST_BRIDGE = hostBridgeAddr;
          TARGETS_JSON = targetsJson;
        };

        script = lib.getExe arrProvision.downloadClients;
      };
    })
  ];
}
