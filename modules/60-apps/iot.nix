
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

      # Containerized Home Assistant (OCI) for full HACS support and Python freedom
      virtualisation.oci-containers.containers."homeassistant" = {
        image = "ghcr.io/home-assistant/home-assistant:stable";
        environment.TZ = "Europe/Berlin";
        volumes = [
          "${cfgHass.stateDir}:/config"
          "/run/postgresql:/run/postgresql" # Mount Postgres socket for Recorder
        ];
        extraOptions = [
          "--network=host" # Required for mDNS/UPnP discovery
        ];
      };

      # Hinweis: Die alte deklarative config (mqtt, http) muss nun manuell in der /var/lib/hass/configuration.yaml
      # vorgenommen werden! Dies beinhaltet auch den Recorder-Block für Postgres:
      # recorder:
      #   db_url: postgresql://hass@/homeassistant?host=/run/postgresql

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
          extraConfig = ''
            import security_headers
            reverse_proxy 127.0.0.1:${toString cfgZigbee.zigbeePort}
          '';
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
    })
  ];
}


