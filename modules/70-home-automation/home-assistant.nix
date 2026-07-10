# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Home Assistant Core — NixOS-Modul mit MQTT-Provisioning
#   services:
#     - home-assistant
#   tags:
#     - iot
#     - home-automation
#   docs:
#     - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
#     - docs/adr/7002-ha-storage-provisioning.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.home-assistant;
  domain = config.my.configs.identity.domain;
  mqttPort = config.my.ports.mqtt;

  # HA ≥2026: broker/port in configuration.yaml removed — MQTT via .storage config entry
  hassMqttProvision = pkgs.writeScript "home-assistant-mqtt-provision" ''
    #!${pkgs.python3}/bin/python3
    import json, os, time
    from pathlib import Path

    STORAGE = Path("${cfg.stateDir}/.storage/core.config_entries")
    _creds = os.environ.get("CREDENTIALS_DIRECTORY")
    if not _creds:
        raise SystemExit("CREDENTIALS_DIRECTORY not set — LoadCredentialEncrypted failed to provide the credential")
    PASSWORD_FILE = Path(_creds) / "homeassistant_mqtt_password"
    ENTRY_ID = "q958mqttmosquitto001"
    MQTT_PORT = ${toString mqttPort}

    if not PASSWORD_FILE.exists():
        raise SystemExit("homeassistant_mqtt_password missing in CREDENTIALS_DIRECTORY")

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
        "discovery_keys": {},
        "domain": "mqtt",
        "entry_id": ENTRY_ID,
        "minor_version": 2,
        "modified_at": now,
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": "Mosquitto (local)",
        "unique_id": None,
        "version": 1,
    }

    STORAGE.parent.mkdir(parents=True, exist_ok=True)
    if STORAGE.exists():
        doc = json.loads(STORAGE.read_text())
        entries = doc.setdefault("data", {}).setdefault("entries", [])
        entries = [e for e in entries if e.get("entry_id") != ENTRY_ID]
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
    uid = pwd.getpwnam("${cfg.user}").pw_uid
    gid = grp.getgrnam("${cfg.group}").gr_gid
    try:
        os.chown(STORAGE, uid, gid)
        os.chmod(STORAGE, 0o600)
        os.chown(STORAGE.parent, uid, gid)
    except OSError as e:
        raise SystemExit(f"Failed to set permissions on {STORAGE}: {e}")
  '';

  hassSmLightProvision = pkgs.writeScript "home-assistant-smlight-provision" ''
    #!${pkgs.python3}/bin/python3
    import json, os, time, urllib.request
    from pathlib import Path

    STORAGE = Path("${cfg.stateDir}/.storage/core.config_entries")
    SMLIGHT_HOST = "${cfg.smlightHost}"
    ENTRY_ID = "q958smlightslzb001"

    try:
        with urllib.request.urlopen("http://" + SMLIGHT_HOST + "/ha_info", timeout=5) as r:
            info = json.loads(r.read())["Info"]
    except Exception as e:
        print("SMLIGHT at " + SMLIGHT_HOST + " unreachable: " + str(e) + " — skipping")
        raise SystemExit(0)

    mac = info["MAC"].lower()
    hostname = info.get("hostname", "SLZB-06M")
    now = time.strftime("%Y-%m-%dT%H:%M:%S.000000+00:00")
    entry = {
        "created_at": now,
        "data": {"host": SMLIGHT_HOST},
        "disabled_by": None,
        "discovery_keys": {},
        "domain": "smlight",
        "entry_id": ENTRY_ID,
        "minor_version": 1,
        "modified_at": now,
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": hostname,
        "unique_id": mac,
        "version": 1,
    }

    STORAGE.parent.mkdir(parents=True, exist_ok=True)
    if STORAGE.exists():
        doc = json.loads(STORAGE.read_text())
        entries = doc.setdefault("data", {}).setdefault("entries", [])
        entries = [e for e in entries if e.get("entry_id") != ENTRY_ID]
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
    uid = pwd.getpwnam("${cfg.user}").pw_uid
    gid = grp.getgrnam("${cfg.group}").gr_gid
    try:
        os.chown(STORAGE, uid, gid)
        os.chmod(STORAGE, 0o600)
        os.chown(STORAGE.parent, uid, gid)
    except OSError as e:
        raise SystemExit(f"Failed to set permissions on {STORAGE}: {e}")
  '';
in
{
  options.my.services.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant (IoT)";
    user = lib.mkOption {
      type = lib.types.str;
      default = "hass";
      description = "Home Assistant system user.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "hass";
      description = "Home Assistant system group.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.home-assistant;
      description = "Home Assistant port.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hass";
      description = "State directory (Tier A).";
    };
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/home-assistant";
      description = "Python cache directory (Tier B).";
    };
    mediaDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-assistant/media";
      description = "Media directory (Tier C).";
    };
    zigbeeDevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SLZB-06 socket or serial path (set in machines/<host>/profile.nix).";
    };
    bluetooth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable bluetooth device access.";
    };
    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to local secrets file.";
    };
    extraComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra components to load.";
    };
    smlightHost = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SMLIGHT device IP/hostname for declarative HA integration provisioning.";
    };
    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.1"
        "::1"
      ];
      description = "List of trusted upstream proxies.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      extraGroups = [
        "dialout"
        "video"
        "media"
      ]
      ++ (lib.optional cfg.bluetooth "bluetooth");
    };
    users.groups.${cfg.group} = { };

    services.home-assistant = {
      enable = true;
      configDir = cfg.stateDir;
      # MQTT via .storage — component must still be in the package (paho-mqtt)
      extraComponents = [ "mqtt" ] ++ cfg.extraComponents;
      config = {
        homeassistant = {
          name = "NixHome";
          unit_system = "metric";
          time_zone = "Europe/Berlin";
          external_url = "https://home.${domain}";
          internal_url = "http://localhost:${toString cfg.port}";
        };
        http = {
          use_x_forwarded_for = true;
          trusted_proxies = cfg.trustedProxies;
        };
      };
    };

    systemd.services.home-assistant-mqtt-provision = {
      description = "Provision Home Assistant MQTT config entry (.storage)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = hassMqttProvision;
        LoadCredentialEncrypted = [
          "homeassistant_mqtt_password:/var/lib/credstore.encrypted/homeassistant_mqtt_password.cred"
        ];
      };
      after = [ "q958-secrets-provision.service" ];
      wants = [ "q958-secrets-provision.service" ];
      before = [ "home-assistant.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.home-assistant-smlight-provision = lib.mkIf (cfg.smlightHost != "") {
      description = "Provision Home Assistant SMLIGHT config entry (.storage)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = hassSmLightProvision;
      };
      after = [ "home-assistant-mqtt-provision.service" ];
      wants = [ "home-assistant-mqtt-provision.service" ];
      before = [ "home-assistant.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.home-assistant = {
      description = lib.mkForce "Home Assistant Core (hardened)";
      environment.PYTHONPYCACHEPREFIX = "${cfg.cacheDir}/pycache";
      serviceConfig = {
        LoadCredential = lib.optional (cfg.secretFile != null) "HA_SECRET:${toString cfg.secretFile}";
        MemoryMax = "2G";
        CPUWeight = 70;
        OOMScoreAdjust = 300;
        # numpy/Pillow native extensions need executable mappings — nixpkgs default breaks HA
        MemoryDenyWriteExecute = lib.mkForce false;
        ReadWritePaths = lib.mkAfter [ cfg.cacheDir ];
        PrivateDevices =
          if (lib.hasPrefix "/dev/" cfg.zigbeeDevice) || cfg.bluetooth then lib.mkForce false else true;
        DeviceAllow =
          (lib.optional (lib.hasPrefix "/dev/" cfg.zigbeeDevice) "${cfg.zigbeeDevice} rw")
          ++ (lib.optional cfg.bluetooth "/dev/rfkill rw")
          ++ [ "/dev/dri/renderD128 rw" ];
      };
      after = lib.mkAfter (
        [
          "q958-secrets-provision.service"
          "home-assistant-mqtt-provision.service"
        ]
        ++ lib.optional (cfg.smlightHost != "") "home-assistant-smlight-provision.service"
      );
      wants = [
        "q958-secrets-provision.service"
        "home-assistant-mqtt-provision.service"
      ]
      ++ lib.optional (cfg.smlightHost != "") "home-assistant-smlight-provision.service";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cacheDir}/pycache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.mediaDir} 0775 ${cfg.user} ${cfg.group} -"
    ];

    my.impermanence.extraPaths = [
      cfg.stateDir
      cfg.cacheDir
    ];
  };
}
