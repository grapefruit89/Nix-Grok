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
  rebuildGuard = import ../../lib/rebuild-guard.nix { inherit lib; };
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
        eventDriven = lib.mkEnableOption ''
          DDNS primär per Netzwerk-Events (Link) + öffentliche IP-Prüfung.
          Hinter NAT: fallbackPeriod + public-ip-check für stille ISP-Wechsel.
        '';
        wanInterface = lib.mkOption {
          type = lib.types.str;
          default = "eno1";
          description = "WAN/LAN-PHY für Link-Events — machines/<host>/network.nix aus profile.lan.interface.";
        };
        period = lib.mkOption {
          type = lib.types.str;
          default = "10m";
          description = "PERIOD wenn eventDriven=false (klassisches Polling).";
        };
        fallbackPeriod = lib.mkOption {
          type = lib.types.str;
          default = "1h";
          description = "PERIOD-Fallback wenn eventDriven=true (stiller ISP-IP-Wechsel).";
        };
        publicIpCheckMin = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Minuten zwischen öffentlichen IP-Vergleichen (NAT-Blind-Spot).";
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

    (lib.mkIf cfgDdns.enable (
      let
        wan = cfgDdns.wanInterface;
        systemctl = "${pkgs.systemd}/bin/systemctl";
        ddnsStaleSyncScript = pkgs.writeShellScript "ddns-stale-sync" ''
          set -euo pipefail
          UPDATES=/var/lib/ddns-updater/updates.json
          LOG=/var/log/ddns-updater/stale-sync.log
          PUBLIC=$(${pkgs.curl}/bin/curl -sf -4 --max-time 15 https://ifconfig.me/ip || true)
          ${pkgs.coreutils}/bin/mkdir -p /var/log/ddns-updater
          if [ -z "$PUBLIC" ]; then
            echo "$(date -Is) no public IP — skip" >> "$LOG"
            exit 0
          fi
          if [ ! -f "$UPDATES" ]; then
            exit 0
          fi
          STALE=$(${pkgs.jq}/bin/jq -r --arg ip "$PUBLIC" '
            [.records[] | select(.ips[-1].ip != null and .ips[-1].ip != $ip) | "\(.domain)/\(.owner)"] | join(",")
          ' "$UPDATES")
          if [ -z "$STALE" ]; then
            exit 0
          fi
          echo "$(date -Is) stale history ($STALE) != $PUBLIC — reset + restart" >> "$LOG"
          ${pkgs.jq}/bin/jq --arg ip "$PUBLIC" '
            .records |= map(
              if (.ips[-1].ip != null and .ips[-1].ip != $ip) then .ips = [] else . end
            )
          ' "$UPDATES" > "$UPDATES.tmp"
          ${pkgs.coreutils}/bin/mv "$UPDATES.tmp" "$UPDATES"
          ${pkgs.coreutils}/bin/chown ddns-updater:ddns-updater "$UPDATES"
        '';
        ddnsTriggerScript = pkgs.writeShellScript "ddns-trigger" ''
          set -euo pipefail
          if [ -f /run/nixos/rebuild-in-progress ]; then exit 0; fi
          if [ -f /run/nixos/switch-to-configuration.lock ]; then exit 0; fi
          RATE=/run/ddns-trigger.last
          NOW=$(${pkgs.coreutils}/bin/date +%s)
          if [ -f "$RATE" ]; then
            ELAPSED=$((NOW - $(${pkgs.coreutils}/bin/cat "$RATE")))
            [ "$ELAPSED" -lt 120 ] && exit 0
          fi
          echo "$NOW" > "$RATE"
          LOCK=/run/lock/ddns-trigger.lock
          ${pkgs.coreutils}/bin/mkdir -p /run/lock
          exec 9>"$LOCK"
          ${pkgs.util-linux}/bin/flock -n 9 || exit 0
          ${ddnsStaleSyncScript}
          ${systemctl} restart ddns-updater.service
        '';
        ddnsPublicIpCheckScript = pkgs.writeShellScript "ddns-public-ip-check" ''
          set -euo pipefail
          STATE=/var/lib/ddns-updater/last-public-ip-check
          LOG=/var/log/ddns-updater/public-ip-check.log
          ${pkgs.coreutils}/bin/mkdir -p /var/log/ddns-updater
          CURRENT=$(${pkgs.curl}/bin/curl -sf -4 --max-time 15 https://ifconfig.me/ip || true)
          if [ -z "$CURRENT" ]; then
            echo "$(date -Is) ifconfig.me unreachable" >> "$LOG"
            exit 0
          fi
          LAST=""
          [ -f "$STATE" ] && LAST=$(${pkgs.coreutils}/bin/cat "$STATE")
          if [ "$CURRENT" = "$LAST" ]; then
            exit 0
          fi
          echo "$(date -Is) public IP $LAST -> $CURRENT — trigger DDNS" >> "$LOG"
          printf '%s' "$CURRENT" > "$STATE"
          ${systemctl} start ddns-trigger.service
        '';
        period = if cfgDdns.eventDriven then cfgDdns.fallbackPeriod else cfgDdns.period;
      in
      {
        services.ddns-updater = {
          enable = true;
          environment = {
            LISTENING_ADDRESS = ":${toString portDdns}";
            PERIOD = period;
          };
        };

        systemd.services.ddns-updater = {
          startLimitIntervalSec = 0;
          after = [
            "q958-secrets-provision.service"
            "network-online.target"
          ];
          requires = [ "q958-secrets-provision.service" ];
          wants = [ "network-online.target" ];
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

        systemd.services.ddns-stale-sync = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS updates.json — veraltete IPs bereinigen";
          path = with pkgs; [
            curl
            jq
            coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = ddnsStaleSyncScript;
          };
        };

        systemd.services.ddns-trigger = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS-Update auslösen (stale-sync + restart ddns-updater)";
          startLimitIntervalSec = 0;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = ddnsTriggerScript;
          };
        };

        systemd.paths.ddns-network-events = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS bei Netzwerk-Events (Link, ${wan})";
          wantedBy = [ "multi-user.target" ];
          unitConfig = rebuildGuard.pathUnitGuard;
          pathConfig = {
            PathExists = [
              "/sys/class/net/${wan}"
              "/sys/class/net/${wan}/carrier"
              "/sys/class/net/${wan}/operstate"
            ];
            PathChanged = [
              "/sys/class/net/${wan}/carrier"
              "/sys/class/net/${wan}/operstate"
            ];
            PathModified = "/run/systemd/netif/leases";
            Unit = "ddns-trigger.service";
            MakeDirectory = false;
          };
        };

        systemd.services.ddns-path-ensure = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS-Path-Unit nach Boot sicherstellen";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.bash}/bin/bash -c '${systemctl} reset-failed ddns-network-events.path 2>/dev/null || true; ${systemctl} start ddns-network-events.path'";
          };
        };

        systemd.paths.ddns-config-changed = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS bei config.json-Änderung (stale-sync + trigger)";
          wantedBy = [ "multi-user.target" ];
          unitConfig = rebuildGuard.pathUnitGuard;
          pathConfig = {
            PathExists = "/var/lib/ddns-updater/config.json";
            PathChanged = "/var/lib/ddns-updater/config.json";
            Unit = "ddns-config-apply.service";
            MakeDirectory = false;
          };
        };

        systemd.services.ddns-config-apply = lib.mkIf cfgDdns.eventDriven {
          description = "DDNS nach Config-Änderung anwenden";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.bash}/bin/bash -c '${systemctl} start ddns-stale-sync.service; ${systemctl} start ddns-trigger.service'";
          };
        };

        systemd.services.ddns-public-ip-check = lib.mkIf cfgDdns.eventDriven {
          description = "Öffentliche IP prüfen (NAT-Blind-Spot)";
          path = with pkgs; [
            curl
            coreutils
            systemd
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = ddnsPublicIpCheckScript;
          };
        };

        systemd.timers.ddns-public-ip-check = lib.mkIf cfgDdns.eventDriven {
          description = "Öffentliche IP alle ${toString cfgDdns.publicIpCheckMin}min prüfen";
          wantedBy = [ "multi-user.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "${toString cfgDdns.publicIpCheckMin}min";
            AccuracySec = "2min";
          };
        };

        users.users.ddns-updater = {
          isSystemUser = true;
          group = "ddns-updater";
          home = "/var/lib/ddns-updater";
        };
        users.groups.ddns-updater = { };

        my.impermanence.extraPaths = [
          "/var/lib/ddns-updater"
          "/var/log/ddns-updater"
        ];
      }
    ))

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

      systemd.paths.dns-guard-secrets = {
        unitConfig = rebuildGuard.pathUnitGuard;
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
        unitConfig = rebuildGuard.pathUnitGuard;
        description = "DNS-Guard wenn DDNS-Konfiguration aktualisiert wird";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathExists = "/var/lib/ddns-updater/config.json";
          PathChanged = "/var/lib/ddns-updater/config.json";
          Unit = "dns-guard.service";
          MakeDirectory = false;
        };
      };

      systemd.paths.dns-guard-ddns-updates = {
        unitConfig = rebuildGuard.pathUnitGuard;
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
        "ddns-stale-sync.service"
        "ddns-trigger.service"
      ];
    })
  ];
}
