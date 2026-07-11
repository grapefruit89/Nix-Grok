{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media.sync.jellyfin;
  cfgSeerr = config.my.media.sync.seerr;
  ports = config.my.ports;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };
  enabled = config.my.services.jellyfin.enable && cfgSeerr.enable;
in
{
  options.my.media.sync.jellyfin = {
    enable = lib.mkEnableOption "Declarative Jellyfin admin bootstrap for Seerr init";
    legacyPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "One-time legacy Jellyfin password for migration to declarative secret.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf enabled {
      my.media.sync.jellyfin.enable = lib.mkDefault true;
    })
    (lib.mkIf (enabled && cfg.enable) {
      systemd.services.arr-sync-jellyfin = {
        description = "Declarative Jellyfin admin bootstrap";
        after = [ "jellyfin.service" ];
        wants = [ "jellyfin.service" ];
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
          JELLYFIN_HOST = "127.0.0.1";
          JELLYFIN_PORT = toString ports.jellyfin;
          JELLYFIN_ADMIN_USER = cfgSeerr.jellyfin.adminUsername;
          JELLYFIN_ADMIN_PASSWORD_FILE = cfgSeerr.jellyfin.adminPasswordFile;
          JELLYFIN_LEGACY_PASSWORD = cfg.legacyPassword;
          JELLYFIN_TV_PATH = cfgSeerr.sonarr.activeDirectory;
          JELLYFIN_MOVIES_PATH = cfgSeerr.radarr.activeDirectory;
        };

        script = lib.getExe arrProvision.jellyfinSetup;
      };
    })
  ];
}
