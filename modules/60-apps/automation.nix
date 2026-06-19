
{ config, lib, ... }:

let
  cfgPaperless = config.my.services.paperless;
  cfgN8n = config.my.services.n8n;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgPaperless.enable {
      services.paperless = {
        enable = true;
        address = "127.0.0.1";
        inherit (cfgPaperless) port;
        inherit (cfgPaperless) dataDir;
        inherit (cfgPaperless) mediaDir;
        inherit (cfgPaperless) consumptionDir;
        environmentFile = "/var/lib/secrets/paperless.env";
        database.createLocally = true;
      };

      services.postgresql = {
        dataDir = "/data/state/postgresql/${config.services.postgresql.package.psqlSchema}";
        settings = {
          PAPERLESS_URL = "https://paperless.${domain}";
          PAPERLESS_ALLOWED_HOSTS = "localhost,127.0.0.1,paperless.${domain}";
          PAPERLESS_TIME_ZONE = "Europe/Berlin";
          PAPERLESS_OCR_LANGUAGE = "deu+eng";
          PAPERLESS_OCR_MODE = "clean";
          PAPERLESS_OCR_OUTPUT_TYPE = "pdfa";
          PAPERLESS_TASK_WORKERS = "2";
          PAPERLESS_THREADS_PER_WORKER = "2";
        };
      };

      systemd.services.paperless-web.serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfgPaperless.dataDir cfgPaperless.mediaDir cfgPaperless.consumptionDir ];
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        ProtectClock = true;
        ProtectHostname = true;
        LockPersonality = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };

      services.caddy.virtualHosts."paperless.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgPaperless.port}
        '';
      };
    })

    (lib.mkIf cfgN8n.enable {
      services.n8n = {
        enable = true;
        environment = {
          N8N_PORT = toString cfgN8n.port;
          N8N_BASE_URL = "https://n8n.${domain}";
          N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
          GENERIC_TIMEZONE = "Europe/Berlin";
        };
      };

      systemd.services.n8n.serviceConfig = {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        ReadWritePaths = lib.mkForce [ cfgN8n.userFolder ];
        LockPersonality = lib.mkForce true;
        CapabilityBoundingSet = lib.mkForce "";
        RestrictNamespaces = lib.mkForce true;
        ProtectClock = lib.mkForce true;
        ProtectHostname = lib.mkForce true;
        RestrictAddressFamilies = lib.mkForce [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };

      services.caddy.virtualHosts."n8n.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgN8n.port}
        '';
      };
    })
  ];
}

