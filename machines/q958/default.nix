# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: q958-Verdrahtung — Module-Imports und my.configs ohne .enable
#   tags:
#     - wiring
#     - q958
#   docs:
#     - docs/adr/015-cpu-power-profiles-daemon-thermald.md
# ---
{
  ...
}:
let
  p = import ./profile.nix;
  primaryUser = import ../../users/jarvis/profile.nix;
  zigbeeSocket = "socket://${p.iot.zigbeeCoordinator.host}:${toString p.iot.zigbeeCoordinator.port}";
  localPath =
    if builtins.pathExists ./profile.local.nix then
      ./profile.local.nix
    else if builtins.pathExists /etc/nixos/machines/q958/profile.local.nix then
      /etc/nixos/machines/q958/profile.local.nix
    else
      null;
  local = if localPath != null then import localPath else { };
  oauth2ClientId = (local.secrets.devKeys.oauth2proxy or { }).clientId or "setup-pending";
in
{
  imports = [
    ./disko-switch.nix
    ./hardware.nix
    ../../modules/00-core
    ../../modules/20-security
    ../../modules/30-storage
    ../../modules/40-observability
    ../../modules/80-agents
    ../../modules/90-policy
    ../../modules/10-network
    ../../modules/50-media
    ../../modules/60-apps
    ../../modules/70-home-automation
    ../../users/jarvis/default.nix
    ./kernel-slim.nix
    ./access.nix
    ./network.nix
    ./storage.nix
    ./secrets.nix
    ./media-secrets.nix
    ./dev-mode.nix
    ./rollout.nix
    ./boot-baseline.nix
    ./welcome-banner.nix
  ];

  nixpkgs.config.allowUnfree = true;
  services.aider.enable = true;
  services.claude-code.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    users.${primaryUser.name} = import ../../users/jarvis/home.nix;
  };

  networking.hostName = p.system.hostName;

  my = {
    creds.keys = [
      "homeassistant_mqtt_password"
      "grafana_secret_key"
      "zigbee2mqtt.env"
      "pocket-id.env"
      "vaultwarden.env"
      "groq_api_key"
      "oauth2-proxy-client-secret"
      "oauth2-proxy-cookie-secret"
      "CF_DNS_API_TOKEN_FILE"
      "cloudflare_api_token"
    ];

    core = {
      nix-tuning.enable = true;
      zram-swap.enable = true;
      kernel-slim = {
        enable = true;
        mode = "homelab-strict";
        homelabProfile = "headless-server";
      };
    };

    security.kernel-hardening = {
      enable = true;
      disableIpv6Stack = false;
      hardenTmp = true;
      hardenDevShm = true;
      hardenRunLock = true;
      enableSlubHardening = true;
      panicOnOops = false;
    };

    configs = {
      identity = {
        user = primaryUser.name;
        domain = p.domain.effective;
      };
      hardware = {
        ramGB = p.hardware.ramGB;
        nixStoreGB = p.hardware.nixStoreGB;
        renderDevice = "/dev/dri/renderD128";
      };
      server = {
        lanIP = p.network.lan.ip;
        netbirdIP = p.network.netbirdIP;
      };
      storage = {
        tierB.mountPoint = p.storage.fastPoolMountPoint;
        tierC = {
          mountPoint = p.storage.tierC.mountPoint;
          labels = p.storage.tierC.labels;
          legacyPrefixes = p.storage.tierC.legacyPrefixes;
        };
      };
      ddns = {
        zone = p.network.ddns.zone;
        record = p.network.ddns.record;
      };
    };

    ports.ssh = p.network.sshPort;

    core.nix-tuning = {
      maxJobs = p.nix.maxJobs;
      cores = p.nix.cores;
      daemonLowPriority = p.nix.daemonLowPriority;
    };

    impermanence = {
      persistentDisk = p.storage.tierA.persist.disk;
      persistMountPoint = p.storage.impermanence.mountPoint;
    };

    alerting = {
      ntfyTopic = p.alerting.ntfyTopic;
      webhookUrl = p.alerting.webhookUrl;
    };

    security = {
      sovereign-unlock = {
        luksDevice = p.storage.luks.device;
        sshPort = p.security.sovereignUnlock.sshPort;
        authorizedKeys = p.security.sovereignUnlock.authorizedKeys;
      };
      firewall = {
        lanCidrs = p.security.firewall.lanCidrs;
        allowedCountries = p.security.firewall.allowedCountries;
        allowLanDns = p.security.firewall.allowLanDns;
        lanInterface = p.network.lan.interface;
        netbirdNotrack = p.security.firewall.netbirdNotrack;
      };
    };

    services = {
      storage.poolMountPoint = p.storage.mediaPoolMountPoint;
      storage-mover = {
        sourceDir = "${p.storage.fastPoolMountPoint}/downloads";
        targetDir = "${p.storage.mediaPoolMountPoint}/downloads";
      };
      restic-backup.healthcheckUrl = p.restic.healthcheckUrl;
      homepage.agentZeroUrl = p.integrations.agentZero.url;
      home-assistant = {
        port = p.iot.homeAssistant.port;
        zigbeeDevice = zigbeeSocket;
        extraComponents = [
          "smlight"
          "cast"
        ];
        smlightHost = "SLZB-06M.local";
      };
      voice-assistant = {
        enable = true;
        tts.enable = true;
        edgeTts.enable = true;
      };
      zigbee-stack = {
        mqttPort = p.iot.zigbeeStack.mqttPort;
        zigbeePort = p.iot.zigbeeStack.zigbeePort;
        zigbeeDevice = zigbeeSocket;
        adapter = p.iot.zigbeeStack.adapter;
        panId = p.iot.zigbeeStack.panId;
      };
      oauth2-proxy.clientId = oauth2ClientId;
      secrets-portal = {
        enable = true;
        secrets = [
          {
            name = "homeassistant_mqtt_password";
            label = "HA / Mosquitto MQTT Passwort";
            description = "Home Assistant + Zigbee2MQTT MQTT-Authentifizierung";
            restart_services = [
              "home-assistant-mqtt-provision"
              "mosquitto"
              "home-assistant"
            ];
          }
          {
            name = "grafana_secret_key";
            label = "Grafana Secret Key";
            description = "Grafana Session-Signing-Key";
            restart_services = [ "grafana" ];
          }
          {
            name = "groq_api_key";
            label = "Groq API Key";
            description = "Faster-Whisper STT via Groq";
            regex = "^gsk_[A-Za-z0-9]{40,80}$";
            restart_services = [ "groq-stt-wyoming" ];
          }
          {
            name = "google_tts_api_key";
            label = "Google TTS API Key";
            description = "Wyoming Google Cloud TTS Engine";
            regex = "^AIzaSy[A-Za-z0-9_-]{33}$";
            restart_services = [
              "google-tts-wyoming"
              "home-assistant-wyoming-provision"
            ];
          }
          {
            name = "pocket-id.env";
            label = "Pocket-ID Env";
            description = "Pocket-ID Umgebungsvariablen (vollständige .env-Datei, KEY=value)";
            restart_services = [ "pocket-id" ];
          }
          {
            name = "vaultwarden.env";
            label = "Vaultwarden Env";
            description = "Vaultwarden Umgebungsvariablen (vollständige .env-Datei)";
            restart_services = [ "vaultwarden" ];
          }
          {
            name = "zigbee2mqtt.env";
            label = "Zigbee2MQTT Env";
            description = "Zigbee2MQTT Umgebungsvariablen (vollständige .env-Datei)";
            restart_services = [ "zigbee2mqtt" ];
          }
          {
            name = "oauth2-proxy-client-secret";
            label = "oauth2-proxy Client Secret";
            description = "OIDC Client Secret (Client ID in profile.local.nix)";
            restart_services = [ "oauth2-proxy" ];
          }
          {
            name = "oauth2-proxy-cookie-secret";
            label = "oauth2-proxy Cookie Secret";
            description = "32-Byte AES-256 Session-Cookie-Seed";
            regex = "^.{32}$";
            restart_services = [ "oauth2-proxy" ];
          }
          {
            name = "CF_DNS_API_TOKEN_FILE";
            label = "Cloudflare ACME Token";
            description = "CF DNS API Token (Rohwert) für Let's Encrypt DNS-01";
            regex = "^[A-Za-z0-9_-]{40,}$";
            restart_services = [ "acme-${p.domain.effective}" ];
          }
        ];
      };
    };
  };

  networking.extraHosts = "${p.iot.zigbeeCoordinator.host} SLZB-06M.local";

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = p.boot.kernelParams;
  };

  system.stateVersion = p.system.stateVersion;
  services.hermes-agent = {
    enable = true;
    settings.model = {
      base_url = "https://openrouter.ai/api/v1";
      # === FREIE MODELLE (kein Verbrauch) ===
      default = "qwen/qwen3-coder:free"; # Code-optimiert, 1M ctx
      # default = "nvidia/nemotron-3-ultra-550b-a55b:free"; # 550B, 1M ctx
      # default = "nvidia/nemotron-3-super-120b-a12b:free"; # 120B, 1M ctx
      # default = "qwen/qwen3-next-80b-a3b-instruct:free";  # allgemein, 262k ctx
      # === GÜNSTIGE BEZAHLTE (Fallback wenn free überlastet) ===
      # default = "deepseek/deepseek-v4-flash";             # $0.09/M, 1M ctx
      # default = "qwen/qwen3-coder-30b-a3b-instruct";     # $0.07/M, 160k ctx
      # default = "deepseek/deepseek-chat-v3-0324";        # $0.20/M, 163k ctx
      # default = "qwen/qwen3-235b-a22b-2507";             # $0.09/M, 262k ctx
    };
    environmentFiles = [ "/var/lib/secrets/hermes.env" ];
    # MCP-Server: zentral in mcp/lib.nix (via modules/80-agents/mcp.nix)
  };

  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
}
