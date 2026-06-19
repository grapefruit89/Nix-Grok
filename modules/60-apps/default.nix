{ config, lib, pkgs, ... }:

let
  cfgVaultwarden = config.my.services.vaultwarden;
  cfgHomepage = config.my.services.homepage;
  cfgHass = config.my.services.home-assistant;
  cfgZigbee = config.my.services.zigbee-stack;
  cfgPaperless = config.my.services.paperless;
  cfgN8n = config.my.services.n8n;
  cfgFilebrowser = config.my.services.filebrowser;
  cfgLinkwarden = config.my.services.linkwarden;
  cfgOpenWebui = config.my.services.open-webui;
  cfgHermes = config.my.services.hermes;
  cfgGrok = config.my.services.grok;

in
{
  imports = [
    ./grok.nix
    ./hermes.nix
    ./vaultwarden.nix
    ./homepage.nix
    ./stealth-landing.nix
    ./filebrowser.nix
    ./linkwarden.nix
    ./open-webui.nix
    ./paperless.nix
    ./n8n.nix
    ./home-assistant.nix
    ./zigbee-stack.nix
  ];

  options.my.services = {
    hermes = {
      enable = lib.mkEnableOption "NousResearch Hermes Agent (Gateway)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8787;
        description = "Hermes Gateway port (nur wenn exposeGatewayPort).";
      };
      containerMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "OCI-Container-Modus (Podman). Falls false: natives NixOS Systemd.";
      };
      exposeGatewayPort = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Gateway-Port in Firewall öffnen (Standard: nur lokal/Tailscale).";
      };
    };
    vaultwarden.enable = lib.mkEnableOption "Vaultwarden Password Manager";
    homepage = {
      enable = lib.mkEnableOption "Homepage Dashboard";
      agentZeroUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional external Agent Zero URL (set in machines/<host>/profile.nix).";
      };
    };

    home-assistant = {
      enable = lib.mkEnableOption "Home Assistant (IoT)";
      user = lib.mkOption { type = lib.types.str; default = "hass"; description = "Home Assistant system user."; };
      group = lib.mkOption { type = lib.types.str; default = "hass"; description = "Home Assistant system group."; };
      port = lib.mkOption { type = lib.types.port; default = 8123; description = "Home Assistant port."; };
      stateDir = lib.mkOption { type = lib.types.str; default = "/var/lib/hass"; description = "State directory (Tier A)."; };
      cacheDir = lib.mkOption { type = lib.types.str; default = "/var/cache/home-assistant"; description = "Python cache directory (Tier B)."; };
      mediaDir = lib.mkOption { type = lib.types.str; default = "/var/lib/home-assistant/media"; description = "Media directory (Tier C)."; };
      zigbeeDevice = lib.mkOption { type = lib.types.str; default = ""; description = "SLZB-06 socket or serial path (set in machines/<host>/profile.nix)."; };
      bluetooth = lib.mkOption { type = lib.types.bool; default = false; description = "Enable bluetooth device access."; };
      secretFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to local secrets file."; };
      extraComponents = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Extra components to load."; };
      trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "127.0.0.1" "::1" ]; description = "List of trusted upstream proxies."; };
    };

    zigbee-stack = {
      enable = lib.mkEnableOption "Zigbee Stack (Mosquitto + Zigbee2MQTT)";
      mqttPort = lib.mkOption { type = lib.types.port; default = 1883; description = "Local Mosquitto port."; };
      zigbeePort = lib.mkOption { type = lib.types.port; default = 8075; description = "Zigbee2MQTT port."; };
      zigbeeDevice = lib.mkOption { type = lib.types.str; default = ""; description = "SLZB-06 socket or serial path (set in machines/<host>/profile.nix)."; };
      adapter = lib.mkOption { type = lib.types.enum [ "ember" "zstack" "deconz" "ezsp" ]; default = "ember"; description = "Ember adapter type."; };
      dataDir = lib.mkOption { type = lib.types.str; default = "/var/lib/zigbee2mqtt"; description = "Zigbee2MQTT data folder."; };
    };

    paperless = {
      enable = lib.mkEnableOption "Paperless-ngx Document Archive";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.paperless; description = "Paperless-ngx web port."; };
      dataDir = lib.mkOption { type = lib.types.str; default = "/data/state/paperless/data"; description = "Data directory."; };
      mediaDir = lib.mkOption { type = lib.types.str; default = "/data/state/paperless/media"; description = "Media directory."; };
      consumptionDir = lib.mkOption { type = lib.types.str; default = "/data/state/paperless/consume"; description = "Consumption directory."; };
    };

    n8n = {
      enable = lib.mkEnableOption "n8n Workflow Automation Platform";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.n8n; description = "n8n port."; };
      userFolder = lib.mkOption { type = lib.types.str; default = "/var/lib/n8n"; description = "n8n state directory."; };
    };

    filebrowser = {
      enable = lib.mkEnableOption "Filebrowser Web File Manager";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.filebrowser; description = "Filebrowser port."; };
      rootPath = lib.mkOption { type = lib.types.str; default = "/mnt/documents"; description = "Root directory to serve."; };
      databasePath = lib.mkOption { type = lib.types.str; default = "/data/state/filebrowser/filebrowser.db"; description = "Database file path."; };
    };

    linkwarden = {
      enable = lib.mkEnableOption "Linkwarden Collaborative Bookmark Manager";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.linkwarden; description = "Linkwarden port."; };
    };

    open-webui = {
      enable = lib.mkEnableOption "Open WebUI for LLM interaction";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.open-webui; description = "Open WebUI port."; };
      ollamaUrl = lib.mkOption { type = lib.types.str; default = "http://127.0.0.1:11434"; description = "Ollama endpoint URL."; };
    };

  };

  # Caddy .enable nur in machines/<host>/rollout.nix — hier nur Hardening
  config = lib.mkIf config.services.caddy.enable {
    systemd.services.caddy = {
      # Blocky → Caddy (ACME + forward_auth ohne Deadlock)
      after = lib.mkAfter (
        lib.optional config.my.services.blocky.enable "blocky.service"
        ++ [ "network-online.target" ]
      );
      wants =
        lib.optional config.my.services.blocky.enable "blocky.service"
        ++ [ "network-online.target" ];
    };

    systemd.services.caddy.serviceConfig = {
      OOMScoreAdjust = lib.mkForce (-900);
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      ProtectSystem = lib.mkForce "strict";
      ProtectHome = lib.mkForce true;
      NoNewPrivileges = lib.mkForce true;
      PrivateTmp = lib.mkForce true;
      PrivateDevices = lib.mkForce true;
      MemoryDenyWriteExecute = lib.mkForce true;
      RestrictNamespaces = lib.mkForce true;
    };
  };
}
