{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgHass = config.my.services.home-assistant;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgHass.enable {
    users.users.${cfgHass.user} = {
      isSystemUser = true;
      inherit (cfgHass) group;
      home = cfgHass.stateDir;
      extraGroups = [ "dialout" "video" "media" ] ++ (lib.optional cfgHass.bluetooth "bluetooth");
    };
    users.groups.${cfgHass.group} = { };

    services.home-assistant = {
      enable = true;
      configDir = cfgHass.stateDir;
      inherit (cfgHass) extraComponents;
      config = {
        homeassistant = {
          name = "NixHome";
          unit_system = "metric";
          time_zone = "Europe/Berlin";
          external_url = "https://home.${domain}";
          internal_url = "http://localhost:${toString cfgHass.port}";
        };
        mqtt = {
          broker = "127.0.0.1";
          port = config.my.ports.mqtt;
        };
        http = {
          server_host = "127.0.0.1";
          use_x_forwarded_for = true;
          trusted_proxies = cfgHass.trustedProxies;
        };
      };
    };

    systemd.services.home-assistant = {
      description = lib.mkForce "Home Assistant Core (hardened)";
      environment.PYTHONPYCACHEPREFIX = "${cfgHass.cacheDir}/pycache";
      serviceConfig = {
        LoadCredential = lib.optional (cfgHass.secretFile != null) "HA_SECRET:${toString cfgHass.secretFile}";
        MemoryMax = "2G";
        CPUWeight = 70;
        OOMScoreAdjust = 300;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        PrivateDevices = if (lib.hasPrefix "/dev/" cfgHass.zigbeeDevice) || cfgHass.bluetooth then lib.mkForce false else true;
        DeviceAllow = (lib.optional (lib.hasPrefix "/dev/" cfgHass.zigbeeDevice) "${cfgHass.zigbeeDevice} rw")
          ++ (lib.optional cfgHass.bluetooth "/dev/rfkill rw")
          ++ [ "/dev/dri/renderD128 rw" ];
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfgHass.stateDir} 0750 ${cfgHass.user} ${cfgHass.group} -"
      "d ${cfgHass.cacheDir} 0750 ${cfgHass.user} ${cfgHass.group} -"
      "d ${cfgHass.cacheDir}/pycache 0750 ${cfgHass.user} ${cfgHass.group} -"
      "d ${cfgHass.mediaDir} 0775 ${cfgHass.user} ${cfgHass.group} -"
    ];

    services.caddy.virtualHosts."home.${domain}" = {
      extraConfig = caddy.proxySecurity cfgHass.port;
    };
  };
}
