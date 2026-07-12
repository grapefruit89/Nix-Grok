{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgProwlarr = config.my.services.prowlarr;
  cfgSync = config.my.media.sync.prowlarr;
  ports = config.my.ports;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };

  prowlarrHost = "127.0.0.1";
  hostBridgeAddr = "127.0.0.1";

  autoApps = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = config.my.services.sonarr.enable;
      port = ports.sonarr;
      host = hostBridgeAddr;
      apiVersion = "v3";
    };
    radarr = {
      enabled = config.my.services.radarr.enable;
      port = ports.radarr;
      host = hostBridgeAddr;
      apiVersion = "v3";
    };
    readarr = {
      enabled = config.my.services.readarr.enable;
      port = ports.readarr;
      host = hostBridgeAddr;
      apiVersion = "v1";
    };
    lidarr = {
      enabled = config.my.services.lidarr.enable;
      port = ports.lidarr;
      host = hostBridgeAddr;
      apiVersion = "v1";
    };
  };

  indexersJson = builtins.toJSON cfgSync.indexers;
  backupIndexersJson = builtins.toJSON cfgSync.backupIndexers;

  appsJson = builtins.toJSON (
    lib.mapAttrsToList (name: app: {
      inherit name;
      inherit (app) port;
      inherit (app) host;
      inherit (app) apiVersion;
      apiKeyFile = "/var/lib/secrets/${name}_api_key";
    }) autoApps
  );

in
{
  options.my.media.sync.prowlarr = {
    enable = lib.mkEnableOption "Deklarativer Prowlarr-Sync (Indexer + Application-Registrierungen)";

    syncLevel = lib.mkOption {
      type = lib.types.enum [
        "addOnly"
        "fullSync"
        "disabled"
      ];
      default = "fullSync";
      description = "Prowlarr-Sync-Level für Arr-Application-Registrierungen (fullSync, addOnly, disabled).";
    };

    indexers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Indexer-Name in Prowlarr.";
            };
            protocol = lib.mkOption {
              type = lib.types.str;
              default = "usenet";
              description = "Protokoll: usenet oder torrent.";
            };
            implementation = lib.mkOption {
              type = lib.types.str;
              default = "Newznab";
              description = "Prowlarr-Indexer-Implementation (z.B. Newznab, Torznab).";
            };
            configContract = lib.mkOption {
              type = lib.types.str;
              default = "NewznabSettings";
              description = "Prowlarr configContract (muss zur Implementation passen).";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "Basis-URL des Indexers.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Pfad zur Datei mit dem Indexer-API-Key (leer = kein Key nötig).";
            };
          };
        }
      );
      default = [ ];
      description = "Usenet/Torrent-Indexer, die deklarativ in Prowlarr registriert werden.";
    };

    backupIndexers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Indexer-Name in den Arr-Apps (wird mit (Backup) suffix empfohlen).";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "Basis-URL des Indexers.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Pfad zur Datei mit dem Indexer-API-Key.";
            };
            categories = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [
                5000
                5100
                5140
                2000
                2100
                2140
              ];
              description = "Newznab-Kategorie-IDs (TV+Movies Standard).";
            };
            targetApps = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arr-App-Namen die diesen Indexer erhalten (leer = alle autoApps).";
            };
          };
        }
      );
      default = [ ];
      description = "Indexer direkt (unabhängig von Prowlarr-Sync) als disabled Backup in Arr-Apps registrieren.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfgProwlarr.enable {
      my.media.sync.prowlarr.enable = lib.mkDefault true;
    })
    (lib.mkIf (cfgProwlarr.enable && cfgSync.enable) {
      systemd.services.arr-sync-prowlarr = {
        description = "Declarative Prowlarr: Indexer + Application Registration";
        after = [
          "prowlarr.service"
        ]
        ++ lib.optional config.my.services.sonarr.enable "sonarr.service"
        ++ lib.optional config.my.services.radarr.enable "radarr.service";
        wants = [ "prowlarr.service" ];
        wantedBy = [ "multi-user.target" ];

        startLimitIntervalSec = 600;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 5;
        };

        environment = {
          PROWLARR_HOST = prowlarrHost;
          PROWLARR_PORT = toString ports.prowlarr;
          PROWLARR_KEY_FILE = "/var/lib/secrets/prowlarr_api_key";
          PROWLARR_DB = "/var/lib/prowlarr/prowlarr.db";
          PROWLARR_VPN_SANDBOX = if config.my.services.usenet-confinement.enable then "1" else "0";
          HOST_BRIDGE = hostBridgeAddr;
          SYNC_LEVEL = cfgSync.syncLevel;
          INDEXERS_JSON = indexersJson;
          APPS_JSON = appsJson;
          BACKUP_INDEXERS_JSON = backupIndexersJson;
        };

        script = lib.getExe arrProvision.prowlarrSync;
      };
    })
  ];
}
