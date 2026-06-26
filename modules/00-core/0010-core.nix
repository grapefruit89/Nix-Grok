# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Boot-Safeguard, Nix-Tuning, ZRAM-Swap, zentrale System-Optionen
#   tags:
#     - core
#     - zram
#     - nix
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfgBoot = config.my.core.boot-safeguard;
  cfgNix = config.my.core.nix-tuning;
  cfgZram = config.my.core.zram-swap;

  ramGB = config.my.configs.hardware.ramGB;
  isLowRam = ramGB <= 4;
  isMidRam = ramGB > 4 && ramGB <= 8;

in

{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my = {
    core = {
      boot-safeguard.enable = lib.mkEnableOption "Boot safeguard generation limits";
      nix-tuning.enable = lib.mkEnableOption "Nix store performance tuning and GC";
      nix-tuning.maxJobs = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Parallele Nix-Jobs (null = RAM-basiert). q958/i3-9100: 4.";
      };
      nix-tuning.cores = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Kerne pro Job (0 = alle). null = RAM-basiert.";
      };
      nix-tuning.daemonLowPriority = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "true = nix-daemon idle (schont Dienste). false = volle Build-Power.";
      };
      zram-swap.enable = lib.mkEnableOption "Aggressive komprimierter ZRAM RAM-swap";
      # kernel-slim Option lebt jetzt nur noch in modules/25-kernel-policy.nix (Duplikat entfernt)
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "development"
        "production"
      ];
      default = "development";
      description = "Overall system mode: development (open) or production (hardened)";
    };

    configs = {
      identity = {
        user = lib.mkOption {
          type = lib.types.str;
          description = "Primary user name (set in users/<name>/profile.nix).";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Primary domain (set in users/<name>/profile.nix).";
        };
      };
      locale = {
        default = lib.mkOption {
          type = lib.types.str;
          default = "de_DE.UTF-8";
          description = "System-wide default locale.";
        };
        language = lib.mkOption {
          type = lib.types.str;
          default = "de";
          description = "System-wide keyboard layout and language code.";
        };
        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/Berlin";
          description = "System-wide timezone.";
        };
      };
      hardware = {
        ramGB = lib.mkOption {
          type = lib.types.int;
          description = "Installed RAM in GB (set in machines/<host>/profile.nix).";
        };
      };
      server = {
        lanIP = lib.mkOption {
          type = lib.types.str;
          description = "Server LAN IP (set in machines/<host>/profile.nix).";
        };
        tailscaleIP = lib.mkOption {
          type = lib.types.str;
          description = "Server Tailscale IP (set in machines/<host>/profile.nix).";
        };
      };
      network = {
        dnsBootstrap = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "tcp-tls:1.1.1.1:853" ];
          description = "Verschlüsselter Blocky-Bootstrap (DoT/DoH) — niemals Klartext-IP.";
        };
        ipv6 = {
          disableOnInterfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Physische Interfaces ohne IPv6 (sysctl + systemd-networkd). Tailscale/WG nicht listen.";
          };
          firewall = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "false = keine CrowdSec/nftables IPv6-Regeln (Homelab nur v4 auf LAN).";
          };
        };
      };
    };

    ports = {
      adguard = lib.mkOption {
        type = lib.types.port;
        default = 3053;
        description = "AdGuard Home port.";
      };
      valkey = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Valkey cache port.";
      };
      ssh = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "SSH port (override via machines/<host>/profile.nix).";
      };
      jellyfin = lib.mkOption {
        type = lib.types.port;
        default = 8096;
        description = "Jellyfin port.";
      };
      jellyseerr = lib.mkOption {
        type = lib.types.port;
        default = 5055;
        description = "Jellyseerr port.";
      };
      sonarr = lib.mkOption {
        type = lib.types.port;
        default = 8989;
        description = "Sonarr port.";
      };
      radarr = lib.mkOption {
        type = lib.types.port;
        default = 7878;
        description = "Radarr port.";
      };
      readarr = lib.mkOption {
        type = lib.types.port;
        default = 8787;
        description = "Readarr port.";
      };
      prowlarr = lib.mkOption {
        type = lib.types.port;
        default = 9696;
        description = "Prowlarr port.";
      };
      sabnzbd = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "SABnzbd port.";
      };
      audiobookshelf = lib.mkOption {
        type = lib.types.port;
        default = 13378;
        description = "Audiobookshelf port (nicht 8000 — Vaultwarden).";
      };
      ddns-updater = lib.mkOption {
        type = lib.types.port;
        default = 10100;
        description = "DDNS-Updater WebUI/API port.";
      };
      vaultwarden = lib.mkOption {
        type = lib.types.port;
        default = 8000;
        description = "Vaultwarden port.";
      };
      homepage = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "Homepage port.";
      };
      mqtt = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "MQTT broker port.";
      };
      zigbee2mqtt = lib.mkOption {
        type = lib.types.port;
        default = 8075;
        description = "Zigbee2MQTT frontend port.";
      };
      pocket-id = lib.mkOption {
        type = lib.types.port;
        default = 8083;
        description = "PocketID port.";
      };
      paperless = lib.mkOption {
        type = lib.types.port;
        default = 28981;
        description = "Paperless-ngx port.";
      };
      n8n = lib.mkOption {
        type = lib.types.port;
        default = 5678;
        description = "n8n port.";
      };
      filebrowser = lib.mkOption {
        type = lib.types.port;
        default = 20001;
        description = "Filebrowser port.";
      };
      linkwarden = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Linkwarden port.";
      };
      open-webui = lib.mkOption {
        type = lib.types.port;
        default = 3080;
        description = "Open WebUI port.";
      };
      forgejo = lib.mkOption {
        type = lib.types.port;
        default = 3010;
        description = "Forgejo HTTP port.";
      };
      semaphore = lib.mkOption {
        type = lib.types.port;
        default = 3015;
        description = "Semaphore HTTP port.";
      };
      cockpit = lib.mkOption {
        type = lib.types.port;
        default = 9090;
        description = "Cockpit admin port.";
      };
      amp = lib.mkOption {
        type = lib.types.port;
        default = 8085;
        description = "AMP Web UI port.";
      };
      crowdsec = lib.mkOption {
        type = lib.types.port;
        default = 8091;
        description = "CrowdSec LAPI port (nicht 8080 — SABnzbd).";
      };
      gatus = lib.mkOption {
        type = lib.types.port;
        default = 8084;
        description = "Gatus Web UI port.";
      };
      scrutiny = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "Scrutiny SMART dashboard port.";
      };
      loki = lib.mkOption {
        type = lib.types.port;
        default = 3100;
        description = "Loki API port.";
      };
      grafana = lib.mkOption {
        type = lib.types.port;
        default = 3005;
        description = "Grafana Web UI port.";
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    {
      # System-Wide Locale Mappings linked to central user settings
      time.timeZone = config.my.configs.locale.timezone;
      i18n.defaultLocale = config.my.configs.locale.default;
      console.keyMap = config.my.configs.locale.language;

      # Enable nix-ld to run unpatched dynamic binaries
      programs.nix-ld.enable = true;
    }

    # ── BOOT SAFEGUARD ────────────────────────────────────────────────────────
    (lib.mkIf cfgBoot.enable {
      # Verhindert Überlauf der EFI System-Partition (ESP) bei strengem 96MB Limit
      boot.loader.systemd-boot.configurationLimit = 5;
    })

    # ── KERNEL SLIMMING → machines/<host>/kernel-slim.nix

    # ── NIX STORE TUNING ──────────────────────────────────────────────────────
    (lib.mkIf cfgNix.enable {
      nix = {
        settings = {
          substituters = [
            "https://cache.nixos.org"
            "https://nix-community.cachix.org"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];

          # Automatische Store-Optimierung
          auto-optimise-store = true;
          builders-use-substitutes = true;
          fallback = true;

          # GC-Roots für schnelles inkrementelles Rebuilding erhalten
          keep-outputs = true;
          keep-derivations = true;

          # Negativ-Cache verkürzen
          narinfo-cache-negative-ttl = 0;

          max-jobs =
            if cfgNix.maxJobs != null then
              lib.mkForce cfgNix.maxJobs
            else if isLowRam then
              lib.mkForce 1
            else if isMidRam then
              lib.mkForce 2
            else
              lib.mkDefault 4;
          cores =
            if cfgNix.cores != null then
              lib.mkForce cfgNix.cores
            else if isLowRam then
              lib.mkForce 1
            else if isMidRam then
              lib.mkForce 2
            else
              lib.mkDefault 0;

          # Build-Timeout gegen hängende Prozesse
          timeout = 3600;
          max-silent-time = 600;

          experimental-features = [
            "nix-command"
            "flakes"
            "auto-allocate-uids"
            "cgroups"
          ];
          sandbox = true;
          trusted-users = [
            "root"
            config.my.configs.identity.user
          ];
        };

        daemonCPUSchedPolicy = if cfgNix.daemonLowPriority then "idle" else "batch";
        daemonIOSchedClass = if cfgNix.daemonLowPriority then "idle" else "best-effort";
        daemonIOSchedPriority = lib.mkIf cfgNix.daemonLowPriority 7;

        # Wöchentlicher automatischer GC
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 7d";
          persistent = true;
        };
      };

      environment.systemPackages = with pkgs; [
        cachix
        nix-tree
        nix-diff
        nix-output-monitor
        nix-du
        # Hygiene-Trio (statix war schon da): statix -> deadnix -> nixfmt-rfc-style
        deadnix
        nixfmt
      ];
    })

    # ── ZRAM COMPRESSED SWAP ──────────────────────────────────────────────────
    (lib.mkIf cfgZram.enable {
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent =
          if ramGB <= 4 then
            75
          else if ramGB <= 8 then
            50
          else
            25;
      };

      # Kernel-Parameter für aggressives und effizientes ZRAM-Paging
      boot.kernel.sysctl = {
        "vm.swappiness" = lib.mkForce 180; # Paging bevorzugt in ZRAM komprimieren
        "vm.page-cluster" = lib.mkDefault 0; # Deaktiviert unnötiges Read-Ahead
        "vm.vfs_cache_pressure" = lib.mkDefault 150; # Aggressiveres Freigeben von Verzeichnis- und Inode-Caches im RAM
      };
    })
  ];
}
