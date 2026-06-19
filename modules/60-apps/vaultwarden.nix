/*
  ---
  id: vaultwarden
  upstream_repo: "dani-garcia/vaultwarden"
  ---
*/

{
  config,
  lib,
  ...
}:

let
  cfgVaultwarden = config.my.services.vaultwarden;
  domain = config.my.configs.identity.domain;
  portVaultwarden = config.my.ports.vaultwarden;

in
{
  config = lib.mkIf cfgVaultwarden.enable {
    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite"; # Lokale SQLite DB fÃ¼r minimale externe Latenz
      environmentFile = "/home/moritz/secrets/vaultwarden.env";

      config = {
        ROCKET_ADDRESS = "127.0.0.2";
        ROCKET_PORT = portVaultwarden;
        DOMAIN = "https://vault.${domain}";

        # Security defaults
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = true;
        SHOW_PASSWORD_HINT = false;
        DISABLE_ADMIN_TOKEN = false; # ErmÃ¶glicht administrative Zugriffe

        # Concurrency
        DATABASE_MAX_CONNS = 10; # WAL mode Concurrency

        # Brute-Force Rate Limiting
        LOGIN_RATELIMIT_MAX_BURST = 10;
        LOGIN_RATELIMIT_SECONDS = 60;

        REQUIRE_DEVICE_EMAIL = false;

        # WebSockets fÃ¼r sofortiges Live-Sync auf GerÃ¤ten
        WEBSOCKET_ENABLED = true;
        WEBSOCKET_ADDRESS = "127.0.0.2";
        WEBSOCKET_PORT = portVaultwarden + 1;

        LOG_LEVEL = "warn";
        EXTENDED_LOGGING = true;
        LOG_FILE = "/var/log/vaultwarden/vaultwarden.log";
        DATA_FOLDER = "/data/state/vaultwarden";
      };
    };

    systemd.services.vaultwarden.serviceConfig.OOMScoreAdjust = -1000;

    # Log-Ordner Bereitstellung
    systemd.tmpfiles.rules = [
      "d /var/log/vaultwarden 0750 vaultwarden vaultwarden -"
    ];

    # Caddy Reverse Proxy mit WebSocket Support fÃ¼r Live-Sync
    services.caddy.virtualHosts."vault.${domain}" = {
      extraConfig = ''
        
                import security_headers
        
                @websocket {
                  header Connection *Upgrade*
                  header Upgrade websocket
                }
                handle @websocket {
                  reverse_proxy 127.0.0.2:${toString (portVaultwarden + 1)}
                }
                reverse_proxy 127.0.0.2:${toString portVaultwarden}
      '';
    };

    # Systemd Security Hardening
    systemd.services.vaultwarden = {
      environment = {
        DATA_FOLDER = "/data/state/vaultwarden";
        ROCKET_ADDRESS = "127.0.0.2";
        ROCKET_PORT = toString portVaultwarden;
        DOMAIN = "https://vault.${domain}";
        WEBSOCKET_ENABLED = "true";
        WEBSOCKET_ADDRESS = "127.0.0.2";
        WEBSOCKET_PORT = toString (portVaultwarden + 1);
        LOG_FILE = "/var/log/vaultwarden/vaultwarden.log";
        WEB_VAULT_ENABLED = "false";
      };
      serviceConfig = {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        ProtectKernelTunables = lib.mkForce true;
        ProtectKernelModules = lib.mkForce true;
        ProtectControlGroups = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        LockPersonality = lib.mkForce true;
        RestrictRealtime = lib.mkForce true;
        RestrictSUIDSGID = lib.mkForce true;
        CapabilityBoundingSet = lib.mkForce "";
        DevicePolicy = lib.mkForce "closed";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = [
          "/data/state/vaultwarden"
          "/var/log/vaultwarden"
        ];
        PrivateUsers = lib.mkForce false;
        EnvironmentFile = lib.mkForce "/home/moritz/secrets/vaultwarden.env";
      };
    };
  };
}
