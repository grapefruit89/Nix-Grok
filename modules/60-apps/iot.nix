# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Home Assistant und Zigbee-Stack (Mosquitto, Zigbee2MQTT)
#   docs:
#     - docs/memory_oom.md
#   services:
#     - home-assistant
#     - mosquitto
#     - zigbee2mqtt
#   tags:
#     - iot
# ---
{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgHass = config.my.services.home-assistant;
  cfgZigbee = config.my.services.zigbee-stack;
  domain = config.my.configs.identity.domain;
  mqttPort = config.my.ports.mqtt;

  # HA ≥2026: broker/port in configuration.yaml removed — MQTT via .storage config entry
  hassMqttProvision = pkgs.writeScript "home-assistant-mqtt-provision" ''
    #!${pkgs.python3}/bin/python3
    import json, os, time
    from pathlib import Path

    STORAGE = Path("${cfgHass.stateDir}/.storage/core.config_entries")
    PASSWORD_FILE = Path("/var/lib/secrets/homeassistant_mqtt_password")
    ENTRY_ID = "q958mqttmosquitto001"
    MQTT_PORT = ${toString mqttPort}

    if not PASSWORD_FILE.exists():
        raise SystemExit("homeassistant_mqtt_password missing — run q958-secrets-provision")

    password = PASSWORD_FILE.read_text().strip()
    now = time.strftime("%Y-%m-%dT%H:%M:%S.000000+00:00")

    entry = {
        "created_at": now,
        "data": {
            "broker": "127.0.0.1",
            "port": int(MQTT_PORT),
            "username": "homeassistant",
            "password": password,
            "protocol": "5",
            "transport": "tcp",
            "discovery": True,
        },
        "disabled_by": None,
        "domain": "mqtt",
        "entry_id": ENTRY_ID,
        "minor_version": 2,
        "modified_at": now,
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "title": "Mosquitto (local)",
        "unique_id": None,
        "version": 1,
    }

    STORAGE.parent.mkdir(parents=True, exist_ok=True)
    if STORAGE.exists():
        doc = json.loads(STORAGE.read_text())
        entries = doc.setdefault("data", {}).setdefault("entries", [])
        entries = [e for e in entries if e.get("entry_id") != ENTRY_ID and e.get("domain") != "mqtt"]
        entries.append(entry)
        doc["data"]["entries"] = entries
    else:
        doc = {
            "version": 1,
            "minor_version": 1,
            "key": "core.config_entries",
            "data": {"entries": [entry]},
        }

    STORAGE.write_text(json.dumps(doc, indent=2) + "\n")
    import grp, pwd
    uid = pwd.getpwnam("${cfgHass.user}").pw_uid
    gid = grp.getgrnam("${cfgHass.group}").gr_gid
    os.chown(STORAGE, uid, gid)
    os.chmod(STORAGE, 0o600)
    os.chown(STORAGE.parent, uid, gid)
  '';

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

      services.home-assistant = {
        enable = true;
        configDir = cfgHass.stateDir;
        # MQTT via .storage — component must still be in the package (paho-mqtt)
        extraComponents = [ "mqtt" ] ++ cfgHass.extraComponents;
        config = {
          homeassistant = {
            name = "NixHome";
            unit_system = "metric";
            time_zone = "Europe/Berlin";
            external_url = "https://home.${domain}";
            internal_url = "http://localhost:${toString cfgHass.port}";
          };
          http = {
            use_x_forwarded_for = true;
            trusted_proxies = cfgHass.trustedProxies;
          };
        };
      };

      systemd.services.home-assistant-mqtt-provision = {
        description = "Provision Home Assistant MQTT config entry (.storage)";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = hassMqttProvision;
        };
        after = [ "q958-secrets-provision.service" ];
        wants = [ "q958-secrets-provision.service" ];
        before = [ "home-assistant.service" ];
        wantedBy = [ "multi-user.target" ];
      };

      systemd.services.home-assistant = {
        description = lib.mkForce "Home Assistant Core (hardened)";
        environment.PYTHONPYCACHEPREFIX = "${cfgHass.cacheDir}/pycache";
        serviceConfig = {
          LoadCredential = lib.optional (cfgHass.secretFile != null) "HA_SECRET:${toString cfgHass.secretFile}";
          MemoryMax = "2G";
          CPUWeight = 70;
          OOMScoreAdjust = 300;
          # numpy/Pillow native extensions need executable mappings — nixpkgs default breaks HA
          MemoryDenyWriteExecute = lib.mkForce false;
          ReadWritePaths = lib.mkAfter [ cfgHass.cacheDir ];
          PrivateDevices = if (lib.hasPrefix "/dev/" cfgHass.zigbeeDevice) || cfgHass.bluetooth then lib.mkForce false else true;
          DeviceAllow = (lib.optional (lib.hasPrefix "/dev/" cfgHass.zigbeeDevice) "${cfgHass.zigbeeDevice} rw")
            ++ (lib.optional cfgHass.bluetooth "/dev/rfkill rw")
            ++ [ "/dev/dri/renderD128 rw" ];
        };
        after = lib.mkAfter [
          "q958-secrets-provision.service"
          "home-assistant-mqtt-provision.service"
        ];
        wants = [
          "q958-secrets-provision.service"
          "home-assistant-mqtt-provision.service"
        ];
      };

      systemd.tmpfiles.rules = [
        "d ${cfgHass.stateDir} 0750 ${cfgHass.user} ${cfgHass.group} -"
        "d ${cfgHass.cacheDir} 0750 ${cfgHass.user} ${cfgHass.group} -"
        "d ${cfgHass.cacheDir}/pycache 0750 ${cfgHass.user} ${cfgHass.group} -"
        "d ${cfgHass.mediaDir} 0775 ${cfgHass.user} ${cfgHass.group} -"
      ];

      my.impermanence.extraPaths = [
        cfgHass.stateDir
        cfgHass.cacheDir
      ];
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
                hashedPasswordFile = "/var/lib/secrets/mosquitto_password";
              };
              homeassistant = {
                hashedPasswordFile = "/var/lib/secrets/mosquitto_hass_password";
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

      };

      my.impermanence.extraPaths = [
        cfgZigbee.dataDir
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
              PrivateDevices = lib.mkForce (if (lib.hasPrefix "/dev/" cfgZigbee.zigbeeDevice) then false else true);
              DeviceAllow = lib.optional (lib.hasPrefix "/dev/" cfgZigbee.zigbeeDevice) "${cfgZigbee.zigbeeDevice} rw";
              RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
              EnvironmentFile = "/var/lib/secrets/zigbee2mqtt.env";
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
