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
  locale = config.my.configs.locale;
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
    libraryRefreshDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Automatic library metadata refresh interval in days (LibraryOptions.AutomaticRefreshIntervalDays).";
    };
    enableChapterExtraction = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable chapter image extraction during library scans (prerequisite for intro detection).";
    };
    enableIntroScan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Trigger Extract Chapter Images + Media Segment Scan after arr-sync-jellyfin.
        Default off — use `systemctl start jellyfin-intro-scan.service` on demand.
      '';
    };
    extraUsers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          passwordFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to file containing the user password.";
          };
        };
      });
      default = [ ];
      description = "Additional Jellyfin users to provision declaratively.";
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
          JELLYFIN_LIBRARY_REFRESH_DAYS = toString cfg.libraryRefreshDays;
          JELLYFIN_ENABLE_CHAPTER_EXTRACTION = if cfg.enableChapterExtraction then "1" else "0";
          JELLYFIN_ENABLE_INTRO_SCAN = if cfg.enableIntroScan then "1" else "0";
          JELLYFIN_METADATA_LANGUAGE = locale.language or "de";
          JELLYFIN_METADATA_COUNTRY = lib.toUpper (lib.substring 3 2 (locale.default or "de_DE.UTF-8"));
          JELLYFIN_EXTRA_USERS_JSON = builtins.toJSON (
            map (u: { name = u.name; password_file = u.passwordFile; }) cfg.extraUsers
          );
        };

        script = lib.getExe arrProvision.jellyfinSetup;
      };

      systemd.services.jellyfin-intro-scan = {
        description = "Jellyfin intro/chapter scan (on demand — heavy CPU/RAM)";
        after = [ "jellyfin.service" ];
        wants = [ "jellyfin.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };

        environment = {
          JELLYFIN_HOST = "127.0.0.1";
          JELLYFIN_PORT = toString ports.jellyfin;
          JELLYFIN_ADMIN_USER = cfgSeerr.jellyfin.adminUsername;
          JELLYFIN_ADMIN_PASSWORD_FILE = cfgSeerr.jellyfin.adminPasswordFile;
          JELLYFIN_INTRO_SCAN_ONLY = "1";
          JELLYFIN_ENABLE_INTRO_SCAN = "1";
        };

        script = lib.getExe arrProvision.jellyfinSetup;
      };
    })
  ];
}