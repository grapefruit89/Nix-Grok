{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media.sync.profiles;
  ports = config.my.ports;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };
  anyArr = config.my.services.sonarr.enable || config.my.services.radarr.enable;
in
{
  options.my.media.sync.profiles = {
    enable = lib.mkEnableOption "Bulk-assign German/English 1080p HEVC profiles to existing library";
  };

  config = lib.mkMerge [
    (lib.mkIf anyArr {
      my.media.sync.profiles.enable = lib.mkDefault true;
    })
    (lib.mkIf (anyArr && cfg.enable) {
      systemd.services.arr-sync-profiles = {
        description = "Assign TRaSH quality profiles to existing Radarr/Sonarr library";
        after =
          lib.optional config.my.services.sonarr.enable "sonarr.service"
          ++ lib.optional config.my.services.radarr.enable "radarr.service"
          ++ lib.optional config.my.services.recyclarr.enable "recyclarr.service"
          ++ [
            "arr-sync-keys.service"
            "arr-sync-settings.service"
          ];
        wants =
          lib.optional config.my.services.sonarr.enable "sonarr.service"
          ++ lib.optional config.my.services.radarr.enable "radarr.service"
          ++ lib.optional config.my.services.recyclarr.enable "recyclarr.service";
        wantedBy = [ "multi-user.target" ];

        startLimitIntervalSec = 600;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = "60s";
          StartLimitBurst = 3;
        };

        environment = {
          ARR_HOST = "127.0.0.1";
          SYNC_SONARR = if config.my.services.sonarr.enable then "1" else "0";
          SYNC_RADARR = if config.my.services.radarr.enable then "1" else "0";
          SONARR_PORT = toString ports.sonarr;
          RADARR_PORT = toString ports.radarr;
          SONARR_KEY_FILE = "/var/lib/secrets/sonarr_api_key";
          RADARR_KEY_FILE = "/var/lib/secrets/radarr_api_key";
        };

        script = lib.getExe arrProvision.profileSync;
      };
    })
  ];
}
