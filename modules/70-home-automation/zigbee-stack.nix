# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Zigbee-Stack — Mosquitto MQTT-Broker + Zigbee2MQTT Bridge
#   services:
#     - mosquitto
#     - zigbee2mqtt
#   tags:
#     - iot
#     - home-automation
# ---
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.services.zigbee-stack;

in
{
  options.my.services.zigbee-stack = {
    enable = lib.mkEnableOption "Zigbee Stack (Mosquitto + Zigbee2MQTT)";
    mqttPort = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "Local Mosquitto port.";
    };
    zigbeePort = lib.mkOption {
      type = lib.types.port;
      default = 8075;
      description = "Zigbee2MQTT port.";
    };
    zigbeeDevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SLZB-06 socket or serial path (set in machines/<host>/profile.nix).";
    };
    adapter = lib.mkOption {
      type = lib.types.enum [
        "ember"
        "zstack"
        "deconz"
        "ezsp"
      ];
      default = "ember";
      description = "Ember adapter type.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/zigbee2mqtt";
      description = "Zigbee2MQTT data folder.";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      mosquitto = {
        enable = true;
        listeners = [
          {
            port = cfg.mqttPort;
            address = "127.0.0.1";
            acl = [ "pattern readwrite #" ];
            settings.allow_anonymous = false;
            users = {
              "zigbee2mqtt" = {
                hashedPasswordFile = "/var/lib/secrets/mosquitto_password";
              };
              homeassistant = {
                hashedPasswordFile = "/var/lib/secrets/mosquitto_hass_password";
              };
            };
          }
        ];
      };

      zigbee2mqtt = {
        enable = true;
        inherit (cfg) dataDir;
        settings = {
          homeassistant = {
            enabled = true;
          };
          permit_join = false;
          mqtt = {
            base_topic = "zigbee2mqtt";
            server = "mqtt://127.0.0.1:${toString cfg.mqttPort}";
            user = "zigbee2mqtt";
          };
          serial = {
            port = cfg.zigbeeDevice;
            inherit (cfg) adapter;
          };
          frontend = {
            port = cfg.zigbeePort;
            host = "127.0.0.1";
          };
          advanced = {
            log_directory = "${cfg.dataDir}/log";
            pan_id = 6699;
          };
        };
      };
    };

    my.impermanence.extraPaths = [
      cfg.dataDir
      "/var/lib/mosquitto"
    ];

    systemd = {
      services = {
        mosquitto = {
          after = [ "q958-secrets-provision.service" ];
          wants = [ "q958-secrets-provision.service" ];
          serviceConfig = {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            ReadWritePaths = [ "/var/lib/mosquitto" ];
            OOMScoreAdjust = -100;
          };
        };

        zigbee2mqtt = {
          after = [ "mosquitto.service" ];
          wants = [ "mosquitto.service" ];
          serviceConfig = {
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            PrivateDevices = lib.mkForce (
              if (lib.hasPrefix "/dev/" cfg.zigbeeDevice) then false else true
            );
            DeviceAllow = lib.optional (lib.hasPrefix "/dev/" cfg.zigbeeDevice) "${cfg.zigbeeDevice} rw";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            EnvironmentFile = "/var/lib/secrets/zigbee2mqtt.env";
          };
        };
      };

      tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 zigbee2mqtt mqtt -"
        "d /var/lib/mosquitto 0750 mosquitto mqtt -"
      ];
    };

    users.users.zigbee2mqtt.extraGroups = [
      "mqtt"
      "dialout"
    ];
    users.users.mosquitto.extraGroups = [ "mqtt" ];
  };
}
