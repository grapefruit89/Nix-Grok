{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgSeerr = config.my.services.jellyseerr;
  cfgJellyfin = config.my.services.jellyfin;
  cfgSync = config.my.media.sync.seerr;
  ports = config.my.ports;
  locale = config.my.configs.locale;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };

  seerrConfigJson = builtins.toJSON (
    {
      apiKeyFile = "/var/lib/secrets/jellyseerr_api_key";
      adminUsername = cfgSync.jellyfin.adminUsername;
      adminPasswordFile = cfgSync.jellyfin.adminPasswordFile;
      adminEmail =
        if cfgSync.jellyfin.adminEmail != "" then
          cfgSync.jellyfin.adminEmail
        else
          cfgSync.jellyfin.adminUsername;
      jellyfinHost = "127.0.0.1";
      jellyfinPort = ports.jellyfin;
      jellyfinUseSsl = false;
      jellyfinUrlBase = "";
      serverType = 2;
      locale = lib.removeSuffix ".UTF-8" (locale.default or "de_DE.UTF-8");
    }
    // lib.optionalAttrs config.my.services.sonarr.enable {
      sonarr = {
        enabled = true;
        name = "Sonarr";
        host = "127.0.0.1";
        port = ports.sonarr;
        apiKeyFile = "/var/lib/secrets/sonarr_api_key";
        activeDirectory = cfgSync.sonarr.activeDirectory;
        isDefault = true;
        syncEnabled = true;
      };
    }
    // lib.optionalAttrs config.my.services.radarr.enable {
      radarr = {
        enabled = true;
        name = "Radarr";
        host = "127.0.0.1";
        port = ports.radarr;
        apiKeyFile = "/var/lib/secrets/radarr_api_key";
        activeDirectory = cfgSync.radarr.activeDirectory;
        isDefault = true;
        syncEnabled = true;
      };
    }
  );

  anyTarget =
    (config.my.services.sonarr.enable || config.my.services.radarr.enable)
    && cfgJellyfin.enable
    && cfgSeerr.enable;

in
{
  options.my.media.sync.seerr = {
    enable = lib.mkEnableOption "Deklarativer Jellyseerr/Seerr-Setup (Jellyfin + Sonarr/Radarr)";

    jellyfin = {
      adminUsername = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Jellyfin-Admin für initiales Seerr-Setup (nur wenn noch nicht initialisiert).";
      };
      adminPasswordFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/secrets/jellyfin_admin_password";
        description = "Datei mit Jellyfin-Admin-Passwort für initiales Seerr-Setup.";
      };
      adminEmail = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "E-Mail für Seerr-Setup (leer = adminUsername).";
      };
    };

    sonarr.activeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/data/media/tv";
      description = "Root-Ordner für Serien in Seerr.";
    };

    radarr.activeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/data/media/movies";
      description = "Root-Ordner für Filme in Seerr.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf anyTarget {
      my.media.sync.seerr.enable = lib.mkDefault true;
    })
    (lib.mkIf (anyTarget && cfgSync.enable) {
      systemd.services.arr-sync-seerr = {
        description = "Declarative Jellyseerr/Seerr setup and *arr wiring";
        after = [
          "arr-sync-jellyfin.service"
          "arr-sync-keys.service"
          "seerr.service"
          "jellyfin.service"
        ]
        ++ lib.optional config.my.services.sonarr.enable "sonarr.service"
        ++ lib.optional config.my.services.radarr.enable "radarr.service";
        wants = [
          "seerr.service"
          "jellyfin.service"
        ];
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
          SEERR_HOST = "127.0.0.1";
          SEERR_PORT = toString ports.jellyseerr;
          SEERR_CONFIG_JSON = seerrConfigJson;
        };

        script = lib.getExe arrProvision.seerrSync;
      };
    })
  ];
}
