{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media.sync.keys;
  ports = config.my.ports;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };
  anyArr =
    config.my.services.sonarr.enable
    || config.my.services.radarr.enable
    || config.my.services.prowlarr.enable
    || config.my.services.sabnzbd.enable;
in
{
  options.my.media.sync.keys = {
    enable = lib.mkEnableOption "Apply declarative *arr/SABnzbd API keys (restart + ini sync)";
  };

  config = lib.mkMerge [
    (lib.mkIf anyArr {
      my.media.sync.keys.enable = lib.mkDefault true;
    })
    (lib.mkIf (anyArr && cfg.enable) {
      systemd.services.arr-sync-keys = {
        description = "Apply declarative *arr/SABnzbd API keys";
        after =
          lib.optional config.my.services.sonarr.enable "sonarr.service"
          ++ lib.optional config.my.services.radarr.enable "radarr.service"
          ++ lib.optional config.my.services.prowlarr.enable "prowlarr.service"
          ++ lib.optional config.my.services.sabnzbd.enable "sabnzbd.service";
        wants =
          lib.optional config.my.services.sonarr.enable "sonarr.service"
          ++ lib.optional config.my.services.radarr.enable "radarr.service"
          ++ lib.optional config.my.services.prowlarr.enable "prowlarr.service"
          ++ lib.optional config.my.services.sabnzbd.enable "sabnzbd.service";
        wantedBy = [ "multi-user.target" ];

        startLimitIntervalSec = 600;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 3;
        };

        environment = {
          ARR_HOST = "127.0.0.1";
          SYNC_SONARR = if config.my.services.sonarr.enable then "1" else "0";
          SYNC_RADARR = if config.my.services.radarr.enable then "1" else "0";
          SYNC_PROWLARR = if config.my.services.prowlarr.enable then "1" else "0";
          SYNC_SABNZBD = if config.my.services.sabnzbd.enable then "1" else "0";
          SONARR_PORT = toString ports.sonarr;
          RADARR_PORT = toString ports.radarr;
          PROWLARR_PORT = toString ports.prowlarr;
          SONARR_KEY_FILE = "/var/lib/secrets/sonarr_api_key";
          RADARR_KEY_FILE = "/var/lib/secrets/radarr_api_key";
          PROWLARR_KEY_FILE = "/var/lib/secrets/prowlarr_api_key";
          SABNZBD_KEY_FILE = "/var/lib/secrets/sabnzbd_api_key";
        };

        script = lib.getExe arrProvision.arrKeysSync;
      };
    })
  ];
}
