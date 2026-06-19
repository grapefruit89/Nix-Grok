{ config, lib, ... }:

let
  cfgN8n = config.my.services.n8n;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkMerge [
    {
      # PostgreSQL SSoT Database Instance
      services.postgresql = {
        enable = true;
        dataDir = "/data/state/postgresql";
        ensureDatabases = [ "homeassistant" ];
        ensureUsers = [
          {
            name = "hass";
            ensureDBOwnership = true;
          }
        ];
      };

      systemd.services.postgresql.serviceConfig = {
        OOMScoreAdjust = -1000; # Kritische SSoT-Datenbank: Niemals von OOM-Killer beenden
      };
    }

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
        OOMScoreAdjust = lib.mkForce (-500);
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
