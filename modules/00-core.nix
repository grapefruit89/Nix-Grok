
# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures critical core subsystem parameters, boot settings, kernel slimming,
# ZRAM swap protection, and store tuning.
# Key decisions -> ADR-00-core.md

{ config, lib, pkgs, ... }:

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
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "development" "production" ];
      default = "development";
      description = "Overall system mode: development (open) or production (hardened)";
    };

    configs = {
      identity = {
        user = lib.mkOption { type = lib.types.str; description = "Primary user name (set in users/<name>/profile.nix)."; };
        domain = lib.mkOption { type = lib.types.str; description = "Primary domain (set in users/<name>/profile.nix)."; };
      };
      locale = {
        default = lib.mkOption { type = lib.types.str; default = "de_DE.UTF-8"; description = "System-wide default locale."; };
        language = lib.mkOption { type = lib.types.str; default = "de"; description = "System-wide keyboard layout and language code."; };
        timezone = lib.mkOption { type = lib.types.str; default = "Europe/Berlin"; description = "System-wide timezone."; };
      };
      hardware = {
        ramGB = lib.mkOption { type = lib.types.int; description = "Installed RAM in GB (set in machines/<host>/profile.nix)."; };
      };
      server = {
        lanIP = lib.mkOption { type = lib.types.str; description = "Server LAN IP (set in machines/<host>/profile.nix)."; };
        tailscaleIP = lib.mkOption { type = lib.types.str; description = "Server Tailscale IP (set in machines/<host>/profile.nix)."; };
      };
      network = {
        dnsDoH = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "https://dns.cloudflare.com/dns-query" ]; description = "List of upstream DNS DoH endpoints."; };
        dnsBootstrap = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" ]; description = "List of bootstrap DNS IPs."; };
        dnsFallback = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" ]; description = "List of fallback DNS IPs."; };
      };
    };

    ports = {
      # 10-network
      valkey = lib.mkOption { type = lib.types.port; default = 1010; description = "Valkey cache port."; };
      pocket-id = lib.mkOption { type = lib.types.port; default = 1020; description = "PocketID port."; };
      
      # 20-security
      ssh = lib.mkOption { type = lib.types.port; default = 22; description = "SSH port (override via machines/<host>/profile.nix)."; };
      caddyAdmin = lib.mkOption { type = lib.types.port; default = 2020; description = "Caddy Admin API port."; };
      
      # 40-observability
      gatus = lib.mkOption { type = lib.types.port; default = 4010; description = "Gatus Web UI port."; };
      loki = lib.mkOption { type = lib.types.port; default = 4020; description = "Loki API port."; };
      grafana = lib.mkOption { type = lib.types.port; default = 4030; description = "Grafana Web UI port."; };

      # 50-media
      jellyfin = lib.mkOption { type = lib.types.port; default = 5010; description = "Jellyfin port."; };
      jellyseerr = lib.mkOption { type = lib.types.port; default = 5020; description = "Jellyseerr port."; };
      sonarr = lib.mkOption { type = lib.types.port; default = 5030; description = "Sonarr port."; };
      radarr = lib.mkOption { type = lib.types.port; default = 5040; description = "Radarr port."; };
      readarr = lib.mkOption { type = lib.types.port; default = 5050; description = "Readarr port."; };
      prowlarr = lib.mkOption { type = lib.types.port; default = 5060; description = "Prowlarr port."; };
      sabnzbd = lib.mkOption { type = lib.types.port; default = 5070; description = "SABnzbd port."; };
      audiobookshelf = lib.mkOption { type = lib.types.port; default = 5080; description = "Audiobookshelf port."; };

      # 60-apps
      vaultwarden = lib.mkOption { type = lib.types.port; default = 6010; description = "Vaultwarden port."; };
      homepage = lib.mkOption { type = lib.types.port; default = 6020; description = "Homepage port."; };
      paperless = lib.mkOption { type = lib.types.port; default = 6030; description = "Paperless-ngx port."; };
      n8n = lib.mkOption { type = lib.types.port; default = 6040; description = "n8n port."; };
      filebrowser = lib.mkOption { type = lib.types.port; default = 6050; description = "Filebrowser port."; };
      linkwarden = lib.mkOption { type = lib.types.port; default = 6060; description = "Linkwarden port."; };
      open-webui = lib.mkOption { type = lib.types.port; default = 6070; description = "Open WebUI port."; };
      forgejo = lib.mkOption { type = lib.types.port; default = 6080; description = "Forgejo HTTP port."; };
      semaphore = lib.mkOption { type = lib.types.port; default = 6090; description = "Semaphore HTTP port."; };
      mqtt = lib.mkOption { type = lib.types.port; default = 6091; description = "MQTT broker port."; };
      zigbee2mqtt = lib.mkOption { type = lib.types.port; default = 6092; description = "Zigbee2MQTT frontend port."; };

      # 70-forge
      cockpit = lib.mkOption { type = lib.types.port; default = 7010; description = "Cockpit admin port."; };

      # 80-gaming
      amp = lib.mkOption { type = lib.types.port; default = 8010; description = "AMP Web UI port."; };
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
    }

    # ── BOOT SAFEGUARD ────────────────────────────────────────────────────────
    (lib.mkIf cfgBoot.enable {
      # Verhindert Überlauf der EFI System-Partition (ESP)
      boot.loader.systemd-boot.configurationLimit = 30;
    })

    # ── PORT COLLISION GUARD ──────────────────────────────────────────────────
    {
      assertions = let
        portAttrs = config.my.ports;
        portList = lib.mapAttrsToList (name: value: value) portAttrs;
        uniquePorts = lib.unique portList;
      in [
        {
          assertion = builtins.length portList == builtins.length uniquePorts;
          message = "KRITISCHER FEHLER: Port-Kollision im Port-Register (config.my.ports) erkannt! Zwei Apps nutzen denselben Port.";
        }
      ];
    }

    # ── KERNEL SLIMMING → machines/<host>/kernel-slim.nix

    # ── STRICT HEADLESS SERVER PURGE ──────────────────────────────────────────
    # Deaktiviert überflüssige Desktop- und Legacy-Dienste tief im System.
    {
      # Kein Legacy NetworkManager (wir nutzen systemd-networkd)
      networking.networkmanager.enable = lib.mkForce false;
      # Keine Legacy DHCP-Clients
      networking.dhcpcd.enable = lib.mkForce false;
      # Keine NixOS Handbücher lokal kompilieren (spart extrem viel RAM/Zeit beim Build)
      documentation.nixos.enable = lib.mkForce false;
      documentation.man.generateCaches = lib.mkForce false;
    }
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
            if cfgNix.maxJobs != null then lib.mkForce cfgNix.maxJobs
            else if isLowRam then lib.mkForce 1
            else if isMidRam then lib.mkForce 2
            else lib.mkDefault 4;
          cores =
            if cfgNix.cores != null then lib.mkForce cfgNix.cores
            else if isLowRam then lib.mkForce 1
            else if isMidRam then lib.mkForce 2
            else lib.mkDefault 0;

          # Build-Timeout gegen hängende Prozesse
          timeout = 3600;
          max-silent-time = 600;

          experimental-features = [ "nix-command" "flakes" "auto-allocate-uids" "cgroups" ];
          sandbox = true;
          trusted-users = [ "root" config.my.configs.identity.user ];
        };

        daemonCPUSchedPolicy =
          if cfgNix.daemonLowPriority then "idle" else "batch";
        daemonIOSchedClass =
          if cfgNix.daemonLowPriority then "idle" else "best-effort";
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
      ];
    })

    # ── ZRAM COMPRESSED SWAP ──────────────────────────────────────────────────
    (lib.mkIf cfgZram.enable {
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent =
          if ramGB <= 4 then 75
          else if ramGB <= 8 then 50
          else 25;
      };

      # Kernel-Parameter für aggressives und effizientes ZRAM-Paging
      boot.kernel.sysctl = {
        "vm.swappiness" = lib.mkForce 180; # Paging bevorzugt in ZRAM komprimieren
        "vm.page-cluster" = lib.mkDefault 0; # Deaktiviert unnötiges Read-Ahead
        "vm.vfs_cache_pressure" = lib.mkDefault 150; # Aggressiveres Freigeben von Verzeichnis- und Inode-Caches im RAM
      };
    })

    # ==========================================================================
    # HARDWARE AUDIT & POWER MANAGEMENT (KISS)
    # ==========================================================================
    {
      services.smartd = {
        enable = true;
        notifications.x11.enable = false;
      };

      services.tlp = {
        enable = true;
        settings = {
          CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
          CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
          CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
          CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
          PCIE_ASPM_ON_AC = "default";
          PCIE_ASPM_ON_BAT = "powersupersave";
        };
      };
    }

    # ==========================================================================
    # SYSTEM UID REGISTRY (PORT = UID)
    # ==========================================================================
    # Jeder Dienst ab Port 1024 bekommt automatische seine Port-Nummer als statische UID/GID.
    {
      users.users = lib.mapAttrs (name: port: {
        uid = lib.mkIf (port >= 1024) (lib.mkDefault port);
        group = lib.mkIf (port >= 1024) name;
        isSystemUser = lib.mkIf (port >= 1024) true;
      }) config.my.ports;

      users.groups = lib.mapAttrs (name: port: {
        gid = lib.mkIf (port >= 1024) port;
      }) config.my.ports;
    }
  ];
}

