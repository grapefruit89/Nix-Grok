{ config, lib, pkgs, ... }:

let
  cfgHass = config.my.services.home-assistant;
  cfgZigbee = config.my.services.zigbee-stack;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgHass.enable {
      users.users.${cfgHass.user} = {
        isSystemUser = true;
        inherit (cfgHass) group;
        home = cfgHass.stateDir;
        extraGroups = [ "dialout" "video" "media" ] ++ (lib.optional cfgHass.bluetooth "bluetooth");
      };
      users.groups.${cfgHass.group} = { };

      # Native NixOS Home Assistant
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
            use_x_forwarded_for = true;
            trusted_proxies = cfgHass.trustedProxies;
          };
          recorder = {
            db_url = "postgresql://hass@/homeassistant?host=/run/postgresql";
          };
        };
      };

      systemd.services.home-assistant = {
        description = lib.mkForce "Home Assistant Core (hardened)";
        environment.PYTHONPYCACHEPREFIX = "${cfgHass.cacheDir}/pycache";
        serviceConfig = {
          OOMScoreAdjust = -500;
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
        extraConfig = ''
          import security_headers
          reverse_proxy 127.0.0.1:${toString cfgHass.port}
        '';
      };
    })

    (lib.mkIf cfgZigbee.enable {
      services = {
        mosquitto = {
          enable = true;
          listeners = [{
            port = cfgZigbee.mqttPort;
            address = "127.0.0.1";
            acl = [ "pattern readwrite #" ];
            settings.allow_anonymous = false;
            users = {
              "zigbee2mqtt" = {
                hashedPasswordFile = "/home/moritz/secrets/mosquitto_password";
              };
            };
          }];
        };

        zigbee2mqtt = {
          enable = true;
          inherit (cfgZigbee) dataDir;
          settings = {
            mqtt = {
              server = "mqtt://127.0.0.1:${toString cfgZigbee.mqttPort}";
              user = "zigbee2mqtt";
              password = "!${cfgZigbee.secretFile} mosquitto_password";
            };
            serial = {
              port = cfgZigbee.device;
              adapter = "zstack";
            };
            advanced = {
              network_key = "!${cfgZigbee.secretFile} network_key";
              pan_id = 6754;
              ext_pan_id = [221, 221, 221, 221, 221, 221, 221, 221];
              homeassistant_legacy_entity_attributes = false;
              legacy_api = false;
              legacy_availability_payload = false;
            };
          };
        };
      };

      systemd.services.zigbee2mqtt.serviceConfig = {
        LoadCredential = lib.optional (cfgZigbee.secretFile != null) "Z2M_SECRET:${toString cfgZigbee.secretFile}";
        MemoryMax = "1G";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfgZigbee.dataDir ];
        PrivateDevices = if (lib.hasPrefix "/dev/" cfgZigbee.device) then lib.mkForce false else true;
        DeviceAllow = lib.optional (lib.hasPrefix "/dev/" cfgZigbee.device) "${cfgZigbee.device} rw";
      };

      services.caddy.virtualHosts."zigbee.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:8080
        '';
      };
    })
  ];
}
