# ---
# meta:
#   id: NIXH-20-SPRT-001
#   layer: 29
#   role: module
#   purpose: secrets-portal — Web-UI für systemd-creds Provisioning und Rotation
#   domain: 20-security
#   uid: 2029
#   socket: /run/secrets-portal/secrets-portal.sock
#   tags:
#     - secrets
#     - security
#     - admin
#     - web
# ---
#
# SCHEMA: 20-security Domäne, Position 29 → UID reserviert = 2029
#
# SICHERHEITSMODELL:
# Phase 1 (aktuell): Läuft als root — erforderlich da systemd-creds encrypt
#   den host-key aus /var/lib/systemd/credential.secret liest (nur root-lesbar).
#   Mitigation: Unix Socket (kein TCP), nur Caddy darf verbinden (internal Zone).
#
# Phase 2 (TODO): Privilege-Separation via zweitem systemd-Service:
#   HTTP-Frontend als User secrets-portal (UID 2029, unprivilegiert, socket-facing)
#   Seal-Daemon als root (socket-activated, nur systemd-creds encrypt, strenge Allowlist)
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.secrets-portal;
  uds = import ../../lib/unix-sockets.nix { inherit lib; };

  portalPkg = pkgs.callPackage ../../packages/secrets-portal { };

  secretDefType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Credential-Name (ohne .cred, identisch mit my.creds.keys Einträgen).";
      };
      label = lib.mkOption {
        type = lib.types.str;
        description = "Lesbare Bezeichnung im UI.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Kurzbeschreibung für welchen Dienst dieser Wert gilt.";
      };
      link = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "URL zur Quelle (z.B. CF Dashboard) — direkt im UI verlinkt.";
      };
      regex = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Go-kompatibles Regex zum Validieren des Formats (client- und server-seitig).";
      };
      validator = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              url = lib.mkOption { type = lib.types.str; };
              header = lib.mkOption {
                type = lib.types.str;
                default = "Authorization";
              };
              header_prefix = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Präfix vor dem Wert im Header (z.B. 'Bearer ' für CF).";
              };
              method = lib.mkOption {
                type = lib.types.str;
                default = "GET";
              };
              expect_status = lib.mkOption {
                type = lib.types.int;
                default = 200;
              };
            };
          }
        );
        default = null;
        description = "Optionaler HTTP-Check der den Key gegen die echte API verifiziert.";
      };
      restart_services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "systemd-Services die nach erfolgreichem Versiegeln neu gestartet werden (z.B. ['ddns-updater' 'caddy']).";
      };
    };
  };

  secretsJson = pkgs.writeText "secrets-portal-config.json" (builtins.toJSON cfg.secrets);

in
{
  options.my.services.secrets-portal = {
    enable = lib.mkEnableOption "secrets-portal Web-UI (systemd-creds Rotation)";

    secrets = lib.mkOption {
      type = lib.types.listOf secretDefType;
      default = [ ];
      description = "Vollständige Metadaten aller verwalteten Credentials.";
      example = [
        {
          name = "cloudflare_api_token";
          label = "Cloudflare API Token";
          description = "DDNS-Updater + ACME-Zertifikate";
          link = "https://dash.cloudflare.com/profile/api-tokens";
          regex = "^[A-Za-z0-9_-]{40,}$";
          validator = {
            url = "https://api.cloudflare.com/client/v4/user/tokens/verify";
            header = "Authorization";
            header_prefix = "Bearer ";
          };
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."secrets-portal/secrets.json".source = secretsJson;

    systemd.services.secrets-portal = {
      description = "secrets-portal — Web-UI für systemd-creds Rotation";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${portalPkg}/bin/secrets-portal";
        Environment = [
          "LISTEN_ADDR=unix:${uds.secrets-portal}"
          "SECRETS_CONFIG=/etc/secrets-portal/secrets.json"
          "CRED_STORE=${config.my.creds.storeDir}"
          "SYSTEMD_CREDS_BIN=${pkgs.systemd}/bin/systemd-creds"
          "SYSTEMCTL_BIN=${pkgs.systemd}/bin/systemctl"
        ];

        # Phase 1: root nötig für systemd-creds host-key
        # Phase 2: User = "secrets-portal" (UID 2029) mit Unix-Socket Seal-Helper
        User = "root";
        Group = "caddy";
        UMask = "0007";

        # Socket-Verzeichnis — nur root schreibt, caddy-Gruppe liest
        RuntimeDirectory = "secrets-portal";
        RuntimeDirectoryMode = "0750";

        # Systemd-Härtung
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        ReadOnlyPaths = "/";
        ReadWritePaths = [ config.my.creds.storeDir ];

        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
