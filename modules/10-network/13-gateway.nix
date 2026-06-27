# ---
# meta:
#   id: NIXH-10-GTW-001
#   layer: 3
#   role: module
#   purpose: DDNS-Updater (Cloudflare) + optional DNS-Guard — kein Cloudflared-Tunnel
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/adr/006-sops-migration-path.md
#   lib:
#     - lib/dns-map.nix
#     - lib/service-factory.nix
#   tags:
#     - gateway
#     - ddns
#     - cloudflare
# ---
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfgDdns = config.my.services.ddns-updater;
  cfgGuard = config.my.services.dns-guard;
  factory = import ../../lib/service-factory.nix {inherit lib;};
  portDdns = config.my.ports.ddns-updater;
  ddnsCfg = config.my.configs.ddns;
in {
  options.my = {
    configs.ddns = {
      zone = lib.mkOption {
        type = lib.types.str;
        default = "m7c5.de";
        description = "Cloudflare-Zone (Parent-Domain).";
      };
      record = lib.mkOption {
        type = lib.types.str;
        default = "nix";
        description = "A-Record-Name → record.zone (z. B. nix.m7c5.de).";
      };
    };

    services = {
      ddns-updater = {
        enable = lib.mkEnableOption "DDNS-Updater (qdm12) — Cloudflare A-Record bei dynamischer IP";
        period = lib.mkOption {
          type = lib.types.str;
          default = "10m";
          description = "Update-Intervall (ddns-updater PERIOD).";
        };
      };
      dns-guard = {
        enable = lib.mkEnableOption "Cloudflare-Wildcard-Konflikt-Check (*.domain) — ohne SOPS";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfgDdns.enable {
      services.ddns-updater = {
        enable = true;
        environment = {
          LISTENING_ADDRESS = ":${toString portDdns}";
          PERIOD = cfgDdns.period;
        };
      };

      systemd.services.ddns-updater = {
        after = ["q958-secrets-provision.service"];
        requires = ["q958-secrets-provision.service"];
        serviceConfig = lib.mkMerge [
          (factory.systemdHardening {
            readWritePaths = ["/var/lib/ddns-updater"];
          })
          {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "ddns-updater";
            Group = lib.mkForce "ddns-updater";
            StateDirectory = lib.mkForce "ddns-updater";
          }
        ];
      };

      users.users.ddns-updater = {
        isSystemUser = true;
        group = "ddns-updater";
        home = "/var/lib/ddns-updater";
      };
      users.groups.ddns-updater = {};

      my.impermanence.extraPaths = ["/var/lib/ddns-updater"];
    })

    (lib.mkIf (cfgGuard.enable && cfgDdns.enable) {
      systemd.services.dns-guard = {
        description = "Cloudflare DNS-Konflikt-Check (*.subdomain)";
        after = [
          "network-online.target"
          "q958-secrets-provision.service"
        ];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "dns-guard";
          ExecStart = pkgs.writeShellScript "dns-guard" ''
            set -euo pipefail
            TOKEN_FILE="/var/lib/secrets/cloudflare_api_token"
            if [ ! -s "$TOKEN_FILE" ]; then
              echo "dns-guard: kein Cloudflare-Token — überspringe"
              exit 0
            fi
            TOKEN=$(cat "$TOKEN_FILE")
            ZONE_DATA=$(${pkgs.curl}/bin/curl -sf -X GET \
              "https://api.cloudflare.com/client/v4/zones?name=${ddnsCfg.zone}" \
              -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
            ZONE_ID=$(${pkgs.jq}/bin/jq -r '.result[0].id // empty' <<< "$ZONE_DATA")
            if [ -z "$ZONE_ID" ]; then
              echo "dns-guard: Zone ${ddnsCfg.zone} nicht gefunden"
              exit 1
            fi
            WILDCARD="${ddnsCfg.record}.${ddnsCfg.zone}"
            CONFLICT=$(${pkgs.curl}/bin/curl -sf \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=*.$WILDCARD" \
              -H "Authorization: Bearer $TOKEN" | ${pkgs.jq}/bin/jq -r '.result | length')
            if [ "$CONFLICT" != "0" ]; then
              echo "dns-guard: WARNUNG — Wildcard *.$WILDCARD existiert (Caddy-Ingress-Konflikt möglich)"
              exit 0
            fi
            echo "dns-guard: ok — kein Wildcard-Konflikt für *.$WILDCARD"
          '';
        };
        path = with pkgs; [
          curl
          jq
          coreutils
        ];
      };

      systemd.timers.dns-guard = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "30min";
          RandomizedDelaySec = "60";
        };
      };
    })
  ];
}
