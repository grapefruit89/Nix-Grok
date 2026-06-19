{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgZigbee = config.my.services.zigbee-stack;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgZigbee.enable {
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
          homeassistant = { enabled = true; };
          permit_join = false;
          mqtt = {
            base_topic = "zigbee2mqtt";
            server = "mqtt://127.0.0.1:${toString cfgZigbee.mqttPort}";
            user = "zigbee2mqtt";
          };
          serial = {
            port = cfgZigbee.zigbeeDevice;
            inherit (cfgZigbee) adapter;
          };
          frontend = {
            port = cfgZigbee.zigbeePort;
            host = "127.0.0.1";
          };
          advanced = {
            log_directory = "${cfgZigbee.dataDir}/log";
            pan_id = 6699;
          };
        };
      };

      caddy.virtualHosts."zigbee.${domain}" = {
        extraConfig = caddy.proxySecurity cfgZigbee.zigbeePort;
      };
    };

    systemd = {
      services = {
        mosquitto.serviceConfig = {
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          ReadWritePaths = [ "/var/lib/mosquitto" ];
          OOMScoreAdjust = -100;
        };

        zigbee2mqtt = {
          after = [ "mosquitto.service" ];
          wants = [ "mosquitto.service" ];
          serviceConfig = {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = lib.mkForce (if (lib.hasPrefix "/dev/" cfgZigbee.zigbeeDevice) then false else true);
            DeviceAllow = lib.optional (lib.hasPrefix "/dev/" cfgZigbee.zigbeeDevice) "${cfgZigbee.zigbeeDevice} rw";
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
            EnvironmentFile = "/home/moritz/secrets/zigbee2mqtt.env";
          };
        };
      };

      tmpfiles.rules = [
        "d ${cfgZigbee.dataDir} 0750 zigbee2mqtt mqtt -"
        "d /var/lib/mosquitto 0750 mosquitto mqtt -"
      ];
    };

    users.users.zigbee2mqtt.extraGroups = [ "mqtt" "dialout" ];
    users.users.mosquitto.extraGroups = [ "mqtt" ];
  };
}

