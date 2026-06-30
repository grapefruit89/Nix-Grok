# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Vaultwarden, Filebrowser, Linkwarden, Open WebUI
#   services:
#     - vaultwarden
#     - filebrowser
#     - linkwarden
#     - open-webui
#   tags:
#     - apps
# ---
{
  config,
  lib,
  ...
}:
let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  cfgVaultwarden = config.my.services.vaultwarden;
  cfgFilebrowser = config.my.services.filebrowser;
  cfgLinkwarden = config.my.services.linkwarden;
  cfgOpenWebui = config.my.services.open-webui;

  domain = config.my.configs.identity.domain;
  dnsMap = import ../../lib/dns-map.nix { inherit domain; };
  vaultHost = dnsMap.host "vaultwarden";
  linksHost = dnsMap.host "linkwarden";
in
{
  config = lib.mkMerge [
    (lib.mkIf cfgVaultwarden.enable {
      services.vaultwarden = {
        enable = true;
        dbBackend = "sqlite"; # Lokale SQLite DB für minimale externe Latenz
        environmentFile = "/var/lib/secrets/vaultwarden.env";

        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = config.my.ports.vaultwarden;
          DOMAIN = "https://${vaultHost}";

          # Security defaults
          SIGNUPS_ALLOWED = false;
          INVITATIONS_ALLOWED = true;
          SHOW_PASSWORD_HINT = false;
          DISABLE_ADMIN_TOKEN = false;

          # Concurrency
          DATABASE_MAX_CONNS = 10; # WAL mode Concurrency

          # Brute-Force Rate Limiting
          LOGIN_RATELIMIT_MAX_BURST = 10;
          LOGIN_RATELIMIT_SECONDS = 60;

          REQUIRE_DEVICE_EMAIL = false;

          # WebSocket-Notifications über Haupt-Socket (ab Vaultwarden 1.29+, kein separater Port mehr)
          WEBSOCKET_ENABLED = true;

          LOG_LEVEL = "warn";
          EXTENDED_LOGGING = true;
          LOG_FILE = "/var/log/vaultwarden/vaultwarden.log";
          DATA_FOLDER = "/var/lib/vaultwarden";
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/vaultwarden 0750 vaultwarden vaultwarden -"
        "d /var/log/vaultwarden 0750 vaultwarden vaultwarden -"
      ];

      my.impermanence.extraPaths = [
        "/var/lib/vaultwarden"
        "/var/log/vaultwarden"
      ];

      systemd.services.vaultwarden.serviceConfig = lib.mkMerge [
        (factory.systemdHardening {
          readWritePaths = [
            "/var/lib/vaultwarden"
            "/var/log/vaultwarden"
          ];
        })
        {
          StateDirectory = "vaultwarden";
          RuntimeDirectory = "vaultwarden";
          RuntimeDirectoryMode = "0700";
          MemoryDenyWriteExecute = lib.mkForce true;
          EnvironmentFile = "/var/lib/secrets/vaultwarden.env";
          Environment = "DATA_FOLDER=/var/lib/vaultwarden";
        }
      ];
    })

    (lib.mkIf cfgFilebrowser.enable {
      services.filebrowser = {
        enable = true;
        settings = {
          inherit (cfgFilebrowser) port;
          address = "127.0.0.1";
          root = cfgFilebrowser.rootPath;
          database = cfgFilebrowser.databasePath;
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/filebrowser 0750 filebrowser filebrowser -"
      ];

      my.impermanence.extraPaths = [ "/var/lib/filebrowser" ];

      systemd.services.filebrowser.serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        OOMScoreAdjust = 300;
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
        ReadWritePaths = [
          "/var/lib/filebrowser"
          cfgFilebrowser.rootPath
        ];
      };
    })

    (lib.mkIf cfgLinkwarden.enable (
      lib.mkMerge [
        {
          services.linkwarden = {
            enable = true;
            inherit (cfgLinkwarden) port;
            environmentFile = "/var/lib/secrets/linkwarden.env";
            environment = {
              NEXTAUTH_URL = "https://${linksHost}/api/v1/auth";
            };
          };
        }

        (factory.mkService {
          inherit config;
          name = "linkwarden";
          inherit (cfgLinkwarden) port;
          mode = "sso";
          caddyOnly = true;
          persistDirs = [ "/var/lib/linkwarden" ];
        })

        {
          systemd.services.linkwarden.serviceConfig = {
            OOMScoreAdjust = 300;
            ProtectClock = true;
            ProtectHostname = true;
          };
        }
      ]
    ))

    (lib.mkIf cfgOpenWebui.enable {
      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        inherit (cfgOpenWebui) port;
        environment = {
          OLLAMA_API_BASE_URL = cfgOpenWebui.ollamaUrl;
          SCARF_NO_ANALYTICS = "True";
          DO_NOT_TRACK = "True";
          ANONYMIZED_TELEMETRY = "False";
        };
      };

      my.impermanence.extraPaths = [ "/var/lib/open-webui" ];

      systemd.services.open-webui.serviceConfig = {
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        OOMScoreAdjust = 200;
      };
    })
  ];
}
