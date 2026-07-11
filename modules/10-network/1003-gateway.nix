# ---
# schema: "100x=Service-Port (ADR-011 Isomorphie)"
# meta:
#   id: NIXH-10-GTW-001
#   layer: 3
#   role: module
#   purpose: DDNS-Updater (Cloudflare) + optional DNS-Guard — kein Cloudflared-Tunnel
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/adr/2006-sops-migration-path.md
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
}:
let
  cfgDdns = config.my.services.ddns-updater;
  cfgGuard = config.my.services.dns-guard;
  factory = import ../../lib/service-factory.nix { inherit lib; };
  portDdns = config.my.ports.ddns-updater;
  ddnsCfg = config.my.configs.ddns;
in
{
  options.my = {
    configs.ddns = {
      zone = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Cloudflare-Zone (Parent-Domain) — aus machines/<host>/profile.nix via my.configs.ddns.";
      };
      record = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "A-Record-Name → record.zone (z. B. nix.m7c5.de). Leer wenn kein Subdomain-Präfix.";
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
        enable = lib.mkEnableOption "Cloudflare-Wildcard-Konflikt-Check (*.domain) — event-getrieben (Boot, Token, DDNS-Config, updates.json IP-Dedup)";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optionals cfgDdns.enable [
        {
          assertion = ddnsCfg.zone != "";
          message = "my.configs.ddns.zone fehlt — machines/<host>/profile.nix → my.configs.ddns setzen.";
        }
      ];
    }

    (lib.mkIf cfgDdns.enable {
      services.ddns-updater = {
        enable = true;
        environment = {
          LISTENING_ADDRESS = ":${toString portDdns}";
          PERIOD = cfgDdns.period;
        };
      };

      systemd.services.ddns-updater = {
        after = [ "q958-secrets-provision.service" ];
        requires = [ "q958-secrets-provision.service" ];
        serviceConfig = lib.mkMerge [
          (factory.systemdHardening {
            readWritePaths = [ "/var/lib/ddns-updater" ];
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
      users.groups.ddns-updater = { };

      my.impermanence.extraPaths = [ "/var/lib/ddns-updater" ];
    })

    (lib.mkIf (cfgGuard.enable && cfgDdns.enable) {
      systemd.services.dns-guard = {
        description = "Cloudflare DNS-Konflikt-Check (*.subdomain)";
        after = [
          "network-online.target"
          "q958-secrets-provision.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "dns-guard";
          ExecStart = pkgs.writeShellScript "dns-guard" ''
            set -euo pipefail
            LOCK_FILE=/run/lock/dns-guard.lock
            ${pkgs.coreutils}/bin/mkdir -p /run/lock
            exec 9>"$LOCK_FILE"
            ${pkgs.util-linux}/bin/flock -w 60 9 || {
              echo "dns-guard: lock timeout after 60s"
              exit 1
            }
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

      # Event-getrieben statt periodischem Timer (deklarative Auslöser).
      systemd.paths.dns-guard-secrets = {
        description = "DNS-Guard nach Cloudflare-Token-Provision oder -Rotation";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = "/var/lib/secrets/cloudflare_api_token";
          PathChanged = "/var/lib/secrets/cloudflare_api_token";
          Unit = "dns-guard.service";
          MakeDirectory = false;
        };
      };

      systemd.paths.dns-guard-ddns-config = {
        description = "DNS-Guard wenn DDNS-Konfiguration aktualisiert wird";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = "/var/lib/ddns-updater/config.json";
          PathChanged = "/var/lib/ddns-updater/config.json";
          Unit = "dns-guard.service";
          MakeDirectory = false;
        };
      };

      # ddns-updater schreibt updates.json jeden PERIOD-Zyklus — Dedup in dns-guard-ddns.service.
      systemd.paths.dns-guard-ddns-updates = {
        description = "DNS-Guard wenn ddns-updater updates.json ändert (nur bei IP-Wechsel)";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = "/var/lib/ddns-updater/updates.json";
          PathChanged = "/var/lib/ddns-updater/updates.json";
          Unit = "dns-guard-ddns.service";
          MakeDirectory = false;
        };
      };

      systemd.services.dns-guard-ddns = {
        description = "DNS-Guard Auslöser — nur bei IP-Änderung in updates.json";
        after = [ "ddns-updater.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "dns-guard-ddns" ''
            set -euo pipefail
            UPDATES=/var/lib/ddns-updater/updates.json
            STATE=/var/lib/dns-guard/last-ddns-ip
            ZONE="${ddnsCfg.zone}"
            OWNER="${ddnsCfg.record}"

            if [[ ! -r "$UPDATES" ]]; then
              echo "dns-guard-ddns: updates.json fehlt — überspringe"
              exit 0
            fi

            CURRENT=$(${pkgs.jq}/bin/jq -r --arg d "$ZONE" --arg o "$OWNER" '
              .records[] | select(.domain == $d and .owner == $o) | .ips[-1].ip // empty
            ' "$UPDATES")

            if [[ -z "$CURRENT" ]]; then
              echo "dns-guard-ddns: kein IP-Eintrag für $OWNER.$ZONE — überspringe"
              exit 0
            fi

            LAST=""
            if [[ -r "$STATE" ]]; then
              LAST="$(${pkgs.coreutils}/bin/cat "$STATE")"
            fi
            if [[ "$CURRENT" == "$LAST" ]]; then
              echo "dns-guard-ddns: IP unverändert ($CURRENT) — überspringe"
              exit 0
            fi

            echo "dns-guard-ddns: IP geändert ($LAST -> $CURRENT) — starte dns-guard"
            ${pkgs.systemd}/bin/systemctl start dns-guard.service
            ${pkgs.coreutils}/bin/mkdir -p /var/lib/dns-guard
            printf '%s' "$CURRENT" > "$STATE"
          '';
        };
        path = with pkgs; [
          jq
          coreutils
          systemd
        ];
      };

      systemd.services.q958-secrets-provision.serviceConfig.OnSuccess = lib.mkOrder 100 [
        "dns-guard.service"
      ];
    })
  ];
}
