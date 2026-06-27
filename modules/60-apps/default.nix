# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Apps-Domain — Submodule, Caddy-Ingress-Härtung
#   lib:
#     - lib/critical-systemd.nix
#     - lib/memory-policy.nix
#   services:
#     - caddy
#   tags:
#     - apps
#     - caddy
# ---
{
  config,
  lib,
  ...
}:
let
  criticalSystemd = import ../../lib/critical-systemd.nix {
    inherit lib;
    oomScore = -900;
  };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
in
{
  imports = [
    ./grok.nix
    ./61-core.nix
    ./automation.nix
    ./hermes.nix
    ./forge.nix
    ./gaming.nix
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
        default = true;
        description = "OCI-Container-Modus — isolierte Umgebung, kein Schreibzugriff auf Host.";
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

    paperless = {
      enable = lib.mkEnableOption "Paperless-ngx Document Archive";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.paperless;
        description = "Paperless-ngx web port.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/paperless";
        description = "Data directory.";
      };
      consumptionDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/paperless/consume";
        description = "Consumption directory.";
      };
    };

    filebrowser = {
      enable = lib.mkEnableOption "Filebrowser Web File Manager";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.filebrowser;
        description = "Filebrowser port.";
      };
      rootPath = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/documents";
        description = "Root directory to serve.";
      };
      databasePath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/filebrowser/filebrowser.db";
        description = "Database file path.";
      };
    };

    linkwarden = {
      enable = lib.mkEnableOption "Linkwarden Collaborative Bookmark Manager";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.linkwarden;
        description = "Linkwarden port.";
      };
    };

    open-webui = {
      enable = lib.mkEnableOption "Open WebUI for LLM interaction";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.open-webui;
        description = "Open WebUI port.";
      };
      ollamaUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:11434";
        description = "Ollama endpoint URL.";
      };
    };
  };

  # Caddy .enable nur in machines/<host>/rollout.nix — hier nur Hardening
  config = lib.mkIf config.services.caddy.enable {
    systemd.services.caddy = {
      # Technitium → PostgreSQL → Caddy (ACME + forward_auth ohne Deadlock)
      after = lib.mkAfter (
        lib.optional config.my.services.technitium-dns-server.enable "technitium-dns-server.service"
        ++ lib.optional config.my.services.pocket-id.enable "postgresql.service"
        ++ [ "network-online.target" ]
      );
      wants =
        lib.optional config.my.services.technitium-dns-server.enable "technitium-dns-server.service"
        ++ [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.caddy.serviceConfig = lib.mkMerge [
      criticalSystemd
      (memory.caddy { })
      {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        RestrictNamespaces = lib.mkForce true;
        # nixpkgs setzt 14400s/10 — für kritischen Ingress aushebeln
        StartLimitIntervalSec = lib.mkForce 0;
        StartLimitBurst = lib.mkForce 0;
        RestartPreventExitStatus = lib.mkForce [ ];
      }
    ];
  };
}
