# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Media-Stack Locale/Config-Sync per systemd oneshot
#   services:
#     - media-stack-config-sync
#   tags:
#     - media
#     - sync
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfgSonarr = config.my.services.sonarr;
  cfgRadarr = config.my.services.radarr;
  cfgProwlarr = config.my.services.prowlarr;
  cfgSabnzbd = config.my.services.sabnzbd;
  cfgJellyfin = config.my.services.jellyfin;
  vpnCfg = config.my.services.vpn-confinement;
  vpnConn = import ../../lib/vpn-connection.nix { inherit lib; };
  waitFor = import ../../lib/wait-for-api.nix { inherit lib pkgs; };
  ports = config.my.ports;

  anyEnabled =
    cfgSonarr.enable
    || cfgRadarr.enable
    || cfgProwlarr.enable
    || cfgSabnzbd.enable
    || cfgJellyfin.enable;

  vpnNsAddress = vpnConn.connectionAddress vpnCfg "prowlarr";
  hostBridgeAddress = vpnConn.hostBridgeAddress vpnCfg "prowlarr";

  mkWait =
    {
      enable,
      name,
      host,
      port,
    }:
    lib.optional enable (
      waitFor.mkScript {
        inherit name;
        url = "http://${host}:${toString port}";
        requireFail = false;
      }
    );

  waitScripts = lib.concatStringsSep " && " (
    mkWait {
      enable = cfgProwlarr.enable;
      name = "prowlarr";
      host = vpnNsAddress;
      port = ports.prowlarr;
    }
    ++ mkWait {
      enable = cfgSonarr.enable;
      name = "sonarr";
      host = "127.0.0.1";
      port = ports.sonarr;
    }
    ++ mkWait {
      enable = cfgRadarr.enable;
      name = "radarr";
      host = "127.0.0.1";
      port = ports.radarr;
    }
    ++ mkWait {
      enable = cfgSabnzbd.enable;
      name = "sabnzbd";
      host = vpnConn.connectionAddress vpnCfg "sabnzbd";
      port = ports.sabnzbd;
    }
  );

in
{
  config = lib.mkIf anyEnabled {
    systemd.services.media-stack-config-sync = {
      description = "Declarative Media Stack Locale and Application Sync Orchestrator";
      after = [
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
        "sabnzbd.service"
        "jellyfin.service"
      ];
      wants = [
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
        "sabnzbd.service"
        "jellyfin.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        curl
        jq
        gnugrep
        coreutils
        python3
        systemd
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      environment = {
        TARGET_LANG = config.my.configs.locale.language;
        TARGET_LOCALE = config.my.configs.locale.default;
        VPN_NS_ADDRESS = vpnNsAddress;
        HOST_BRIDGE_ADDRESS = hostBridgeAddress;
        PORT_PROWLARR = toString ports.prowlarr;
        PORT_SONARR = toString ports.sonarr;
        PORT_RADARR = toString ports.radarr;
        PORT_SABNZBD = toString ports.sabnzbd;
      };

      script =
        (lib.optionalString (waitScripts != "") "${waitScripts}\n") + builtins.readFile ./sync-script.sh;
    };
  };
}
