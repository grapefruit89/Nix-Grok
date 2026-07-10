# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Vaultwarden, Filebrowser, Shiori, Open WebUI
#   services:
#     - vaultwarden
#     - filebrowser
#     - shiori
#     - open-webui
#   tags:
#     - apps
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  cfgVaultwarden = config.my.services.vaultwarden;
  cfgFilebrowser = config.my.services.filebrowser;
  cfgShiori = config.my.services.shiori;
  cfgOpenWebui = config.my.services.open-webui;

  domain = config.my.configs.identity.domain;
  dnsMap = import ../../lib/dns-map.nix { inherit domain; };
  vaultHost = dnsMap.host "vaultwarden";
in
{
  config = lib.mkMerge [
    (lib.mkIf cfgVaultwarden.enable {
      services.vaultwarden = {
        enable = true;
        dbBackend = "sqlite";
        environmentFile = "/var/lib/secrets/vaultwarden.env";

        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = config.my.ports.vaultwarden;
          DOMAIN = "https://${vaultHost}";

          SIGNUPS_ALLOWED = false;
          INVITATIONS_ALLOWED = true;
          SHOW_PASSWORD_HINT = false;
          DISABLE_ADMIN_TOKEN = false;
          DATABASE_MAX_CONNS = 10;
          LOGIN_RATELIMIT_MAX_BURST = 10;
          LOGIN_RATELIMIT_SECONDS = 60;
          REQUIRE_DEVICE_EMAIL = false;
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

    (lib.mkIf cfgShiori.enable (
      lib.mkMerge [
        {
          services.shiori = {
            enable = true;
            inherit (cfgShiori) port;
            address = "127.0.0.1";
            # SHIORI_HTTP_SECRET_KEY ist Pflicht seit NixOS 24.05 — ohne diese Datei startet shiori nicht
            environmentFile = "/var/lib/secrets/shiori.env";
          };
        }

        (factory.mkService {
          inherit config;
          name = "shiori";
          inherit (cfgShiori) port;
          mode = "sso";
          caddyOnly = true;
          persistDirs = [ "/var/lib/shiori" ];
        })

        {
          systemd.services.shiori.serviceConfig = {
            OOMScoreAdjust = 300;
            ProtectClock = true;
            ProtectHostname = true;
          };
        }

        {
          systemd.services.shiori-secret-init = {
            description = "Generate SHIORI_HTTP_SECRET_KEY on first boot";
            before = [ "shiori.service" ];
            wantedBy = [ "shiori.service" ];
            unitConfig.ConditionPathExists = "!/var/lib/secrets/shiori.env";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.writeShellScript "shiori-secret-init" ''
                install -m 600 /dev/null /var/lib/secrets/shiori.env
                printf 'SHIORI_HTTP_SECRET_KEY=%s\n' \
                  "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
                  >> /var/lib/secrets/shiori.env
              ''}";
            };
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
