# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Home Assistant Core — NixOS-Modul mit .storage Provisioning
#   services:
#     - home-assistant
#     - home-assistant-mqtt-provision
#     - home-assistant-smlight-provision
#     - home-assistant-wyoming-provision
#     - home-assistant-pipeline-provision
#   tags:
#     - iot
#     - home-automation
#   docs:
#     - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
#     - docs/adr/7002-ha-storage-provisioning.md
#     - docs/superpowers/specs/2026-07-09-home-assistant-declarative-design.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.home-assistant;
  voiceCfg = config.my.services.voice-assistant;
  locale = config.my.configs.locale;
  domain = config.my.configs.identity.domain;
  mqttPort = config.my.ports.mqtt;

  edgeTtsLang =
    let
      prefix = lib.substring 0 5 voiceCfg.edgeTts.voice;
    in
    lib.replaceStrings [ "-" ] [ "_" ] (lib.toLower prefix);

  dashboardSkeleton = pkgs.writeText "ui-lovelace.yaml" ''
    views:
      - title: Home
        path: home
        icon: mdi:home
        cards: []
  '';

  pythonStorageHelper = ''
    import grp, json, os, pwd, time
    from pathlib import Path

    def _chown_storage(path: Path, uid: int, gid: int) -> None:
        try:
            os.chown(path, uid, gid)
            os.chmod(path, 0o600)
            os.chown(path.parent, uid, gid)
        except OSError as e:
            raise SystemExit(f"Failed to set permissions on {path}: {e}")

    def upsert_config_entries(storage: Path, managed_ids: set, new_entries: list) -> None:
        now = time.strftime("%Y-%m-%dT%H:%M:%S.000000+00:00")
        for entry in new_entries:
            entry.setdefault("created_at", now)
            entry.setdefault("modified_at", now)

        storage.parent.mkdir(parents=True, exist_ok=True)
        if storage.exists():
            doc = json.loads(storage.read_text())
            entries = doc.setdefault("data", {}).setdefault("entries", [])
            entries = [e for e in entries if e.get("entry_id") not in managed_ids]
            entries.extend(new_entries)
            doc["data"]["entries"] = entries
        else:
            doc = {
                "version": 1,
                "minor_version": 1,
                "key": "core.config_entries",
                "data": {"entries": new_entries},
            }

        storage.write_text(json.dumps(doc, indent=2) + "\n")
        uid = pwd.getpwnam("${cfg.user}").pw_uid
        gid = grp.getgrnam("${cfg.group}").gr_gid
        _chown_storage(storage, uid, gid)
  '';

  hassMqttProvision = pkgs.writeScript "home-assistant-mqtt-provision" ''
    #!${pkgs.python3}/bin/python3
    ${pythonStorageHelper}
    from pathlib import Path

    STORAGE = Path("${cfg.stateDir}/.storage/core.config_entries")
    _creds = os.environ.get("CREDENTIALS_DIRECTORY")
    if not _creds:
        raise SystemExit("CREDENTIALS_DIRECTORY not set — LoadCredentialEncrypted failed to provide the credential")
    PASSWORD_FILE = Path(_creds) / "homeassistant_mqtt_password"
    ENTRY_ID = "q958mqttmosquitto001"

    if not PASSWORD_FILE.exists():
        raise SystemExit("homeassistant_mqtt_password missing in CREDENTIALS_DIRECTORY")

    password = PASSWORD_FILE.read_text().strip()
    entry = {
        "data": {
            "broker": "127.0.0.1",
            "port": ${toString mqttPort},
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
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": "Mosquitto (local)",
        "unique_id": None,
        "version": 1,
    }
    upsert_config_entries(STORAGE, {ENTRY_ID}, [entry])
  '';

  hassSmLightProvision = pkgs.writeScript "home-assistant-smlight-provision" ''
    #!${pkgs.python3}/bin/python3
    import json, urllib.request
    ${pythonStorageHelper}
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
    entry = {
        "data": {"host": SMLIGHT_HOST},
        "disabled_by": None,
        "discovery_keys": {},
        "domain": "smlight",
        "entry_id": ENTRY_ID,
        "minor_version": 1,
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": hostname,
        "unique_id": mac,
        "version": 1,
    }
    upsert_config_entries(STORAGE, {ENTRY_ID}, [entry])
  '';

  wyomingManagedIds = [
    "q958wyominggroqstt001"
    "q958wyomingedgetts001"
    "q958wyominggoogletts001"
  ];

  hassWyomingProvision = pkgs.writeScript "home-assistant-wyoming-provision" ''
    #!${pkgs.python3}/bin/python3
    ${pythonStorageHelper}
    from pathlib import Path

    STORAGE = Path("${cfg.stateDir}/.storage/core.config_entries")
    MANAGED = {
        ${lib.concatStringsSep "\n        " (map (id: "\"${id}\",") wyomingManagedIds)}
    }

    def wyoming_entry(entry_id: str, port: int, title: str) -> dict:
        return {
            "data": {"host": "127.0.0.1", "port": port},
            "disabled_by": None,
            "discovery_keys": {},
            "domain": "wyoming",
            "entry_id": entry_id,
            "minor_version": 1,
            "options": {},
            "pref_disable_new_entities": False,
            "pref_disable_polling": False,
            "source": "user",
            "subentries": [],
            "title": title,
            "unique_id": None,
            "version": 1,
        }

    entries = [
        wyoming_entry("q958wyominggroqstt001", ${toString voiceCfg.port}, "groq-whisper"),
        wyoming_entry("q958wyomingedgetts001", ${toString voiceCfg.edgeTts.port}, "edge-tts"),
    ]
    if Path("/var/lib/credstore.encrypted/google_tts_api_key.cred").exists():
        entries.append(wyoming_entry("q958wyominggoogletts001", ${toString voiceCfg.tts.port}, "google-tts"))
    upsert_config_entries(STORAGE, MANAGED, entries)
  '';

  hassPipelineProvision = pkgs.writeScript "home-assistant-pipeline-provision" ''
    #!${pkgs.python3}/bin/python3
    import grp, json, os, pwd
    from pathlib import Path

    STORAGE = Path("${cfg.stateDir}/.storage/assist_pipeline.pipelines")
    PIPELINE_ID = "q958assistpipeline001"

    pipeline = {
        "conversation_engine": "conversation.home_assistant",
        "conversation_language": "${locale.language}",
        "id": PIPELINE_ID,
        "language": "${locale.language}",
        "name": "Assist (${locale.language})",
        "stt_engine": "stt.groq_whisper",
        "stt_language": "${locale.language}",
        "tts_engine": "tts.edge_tts",
        "tts_language": "${edgeTtsLang}",
        "tts_voice": "${voiceCfg.edgeTts.voice}",
        "wake_word_entity": None,
        "wake_word_id": None,
        "prefer_local_intents": False,
    }

    STORAGE.parent.mkdir(parents=True, exist_ok=True)
    if STORAGE.exists():
        doc = json.loads(STORAGE.read_text())
        items = doc.setdefault("data", {}).setdefault("items", [])
        items = [p for p in items if p.get("id") != PIPELINE_ID]
        items.append(pipeline)
        doc["data"]["items"] = items
    else:
        doc = {
            "version": 1,
            "minor_version": 2,
            "key": "assist_pipeline.pipelines",
            "data": {
                "items": [pipeline],
                "preferred_item": PIPELINE_ID,
            },
        }

    doc["data"]["preferred_item"] = PIPELINE_ID
    STORAGE.write_text(json.dumps(doc, indent=2) + "\n")

    uid = pwd.getpwnam("${cfg.user}").pw_uid
    gid = grp.getgrnam("${cfg.group}").gr_gid
    try:
        os.chown(STORAGE, uid, gid)
        os.chmod(STORAGE, 0o644)
        os.chown(STORAGE.parent, uid, gid)
    except OSError as e:
        raise SystemExit(f"Failed to set permissions on {STORAGE}: {e}")
  '';

  smlightEnabled = cfg.smlightHost != "";
  voiceEnabled = voiceCfg.enable;

  provisionChain = [
    "home-assistant-mqtt-provision.service"
  ]
  ++ lib.optional smlightEnabled "home-assistant-smlight-provision.service"
  ++ lib.optional voiceEnabled "home-assistant-wyoming-provision.service"
  ++ lib.optional voiceEnabled "home-assistant-pipeline-provision.service";

  wyomingAfter =
    if smlightEnabled then
      "home-assistant-smlight-provision.service"
    else
      "home-assistant-mqtt-provision.service";
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
    renderDevice = lib.mkOption {
      type = lib.types.str;
      default = config.my.configs.hardware.renderDevice;
      description = "GPU render node for VA-API. Leer = kein GPU-Zugriff (PrivateDevices bleibt an).";
    };
    purgeKeepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Recorder: Tage bis zur automatischen DB-Bereinigung.";
    };
    helperEntities = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        HA Helper-Entities als Nix-Attrset — wird in configuration.yaml gemergt.
        Beispiel: { input_boolean.guest_mode = { name = "Gäste-Modus"; }; }
      '';
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
      extraComponents = [ "mqtt" ] ++ lib.optional voiceCfg.enable "wyoming" ++ cfg.extraComponents;
      config = {
        homeassistant = {
          name = "NixHome";
          unit_system = "metric";
          time_zone = locale.timezone;
          language = locale.language;
          country = "DE";
          currency = "EUR";
          external_url = "https://home.${domain}";
          internal_url = "http://localhost:${toString cfg.port}";
        };
        http = {
          server_port = cfg.port;
          use_x_forwarded_for = true;
          trusted_proxies = cfg.trustedProxies;
          ip_ban_enabled = true;
          login_attempts_threshold = 5;
        };
        lovelace = {
          resource_mode = "yaml";
          dashboards = {
            nix-home = {
              mode = "yaml";
              filename = "ui-lovelace.yaml";
              title = "Home";
              icon = "mdi:home";
              show_in_sidebar = true;
            };
          };
        };
        recorder = {
          purge_keep_days = cfg.purgeKeepDays;
          auto_purge = true;
        };
        logbook = { };
        history = { };
        logger = {
          default = "warning";
          logs = {
            "homeassistant.components.mqtt" = "info";
            "homeassistant.components.wyoming" = "info";
          };
        };
        frontend = { };
      }
      // cfg.helperEntities;
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

    systemd.services.home-assistant-smlight-provision = lib.mkIf smlightEnabled {
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

    systemd.services.home-assistant-wyoming-provision = lib.mkIf voiceEnabled {
      description = "Provision Home Assistant Wyoming config entries (.storage)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = hassWyomingProvision;
      };
      after = [ wyomingAfter ];
      wants = [ wyomingAfter ];
      before = [ "home-assistant.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.home-assistant-pipeline-provision = lib.mkIf voiceEnabled {
      description = "Provision Home Assistant Assist pipeline (.storage)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = hassPipelineProvision;
      };
      after = [ "home-assistant-wyoming-provision.service" ];
      wants = [ "home-assistant-wyoming-provision.service" ];
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
        MemoryDenyWriteExecute = lib.mkForce false;
        ReadWritePaths = lib.mkAfter [ cfg.cacheDir ];
        PrivateDevices =
          if (lib.hasPrefix "/dev/" cfg.zigbeeDevice) || cfg.bluetooth || (cfg.renderDevice != "") then
            lib.mkForce false
          else
            true;
        DeviceAllow =
          (lib.optional (lib.hasPrefix "/dev/" cfg.zigbeeDevice) "${cfg.zigbeeDevice} rw")
          ++ (lib.optional cfg.bluetooth "/dev/rfkill rw")
          ++ (lib.optional (cfg.renderDevice != "") "${cfg.renderDevice} rw");
      };
      after = lib.mkAfter ([ "q958-secrets-provision.service" ] ++ provisionChain);
      wants = [
        "q958-secrets-provision.service"
      ]
      ++ provisionChain;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cacheDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.cacheDir}/pycache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.mediaDir} 0775 ${cfg.user} ${cfg.group} -"
      "C ${cfg.stateDir}/ui-lovelace.yaml 0640 ${cfg.user} ${cfg.group} - ${dashboardSkeleton}"
    ];

    my.impermanence.extraPaths = [
      cfg.stateDir
      cfg.cacheDir
    ];
  };
}
