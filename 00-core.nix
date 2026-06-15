
# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures critical core subsystem parameters, boot settings, kernel slimming,
# ZRAM swap protection, and store tuning to optimize the Fujitsu Q958 homelab.
# Key decisions -> ADR-00-core.md

{ config, lib, pkgs, ... }:

let
  cfgBoot = config.my.core.boot-safeguard;
  cfgKernel = config.my.core.kernel-slim;
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
      kernel-slim.enable = lib.mkEnableOption "Fujitsu Q958 kernel slimming (saves ~300MB RAM)";
      nix-tuning.enable = lib.mkEnableOption "Nix store performance tuning and GC";
      zram-swap.enable = lib.mkEnableOption "Aggressive komprimierter ZRAM RAM-swap";
    };

    mode = lib.mkOption {
      type = lib.types.enum [ "development" "production" ];
      default = "development";
      description = "Overall system mode: development (open) or production (hardened)";
    };

    configs = {
      identity = {
        user = lib.mkOption { type = lib.types.str; default = "moritz"; description = "Primary user name."; };
        domain = lib.mkOption { type = lib.types.str; default = "m7c5.de"; description = "Primary domain."; };
      };
      locale = {
        default = lib.mkOption { type = lib.types.str; default = "de_DE.UTF-8"; description = "System-wide default locale."; };
        language = lib.mkOption { type = lib.types.str; default = "de"; description = "System-wide keyboard layout and language code."; };
        timezone = lib.mkOption { type = lib.types.str; default = "Europe/Berlin"; description = "System-wide timezone."; };
      };
      hardware = {
        ramGB = lib.mkOption { type = lib.types.int; default = 16; description = "Installed RAM in GB."; };
      };
      server = {
        lanIP = lib.mkOption { type = lib.types.str; default = "192.168.1.100"; description = "Server LAN IP address."; };
        tailscaleIP = lib.mkOption { type = lib.types.str; default = "100.64.0.1"; description = "Server Tailscale IP address."; };
      };
      network = {
        dnsDoH = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "https://dns.cloudflare.com/dns-query" ]; description = "List of upstream DNS DoH endpoints."; };
        dnsBootstrap = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" ]; description = "List of bootstrap DNS IPs."; };
        dnsFallback = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" ]; description = "List of fallback DNS IPs."; };
      };
    };

    ports = {
      adguard = lib.mkOption { type = lib.types.port; default = 3053; description = "AdGuard Home port."; };
      valkey = lib.mkOption { type = lib.types.port; default = 6379; description = "Valkey cache port."; };
      ssh = lib.mkOption { type = lib.types.port; default = 53844; description = "SSH port."; };
      jellyfin = lib.mkOption { type = lib.types.port; default = 8096; description = "Jellyfin port."; };
      jellyseerr = lib.mkOption { type = lib.types.port; default = 5055; description = "Jellyseerr port."; };
      sonarr = lib.mkOption { type = lib.types.port; default = 8989; description = "Sonarr port."; };
      radarr = lib.mkOption { type = lib.types.port; default = 7878; description = "Radarr port."; };
      readarr = lib.mkOption { type = lib.types.port; default = 8787; description = "Readarr port."; };
      prowlarr = lib.mkOption { type = lib.types.port; default = 9696; description = "Prowlarr port."; };
      sabnzbd = lib.mkOption { type = lib.types.port; default = 8080; description = "SABnzbd port."; };
      vaultwarden = lib.mkOption { type = lib.types.port; default = 8000; description = "Vaultwarden port."; };
      homepage = lib.mkOption { type = lib.types.port; default = 8082; description = "Homepage port."; };
      mqtt = lib.mkOption { type = lib.types.port; default = 1883; description = "MQTT broker port."; };
      zigbee2mqtt = lib.mkOption { type = lib.types.port; default = 8075; description = "Zigbee2MQTT frontend port."; };
      pocket-id = lib.mkOption { type = lib.types.port; default = 8083; description = "PocketID port."; };
      paperless = lib.mkOption { type = lib.types.port; default = 28981; description = "Paperless-ngx port."; };
      n8n = lib.mkOption { type = lib.types.port; default = 5678; description = "n8n port."; };
      filebrowser = lib.mkOption { type = lib.types.port; default = 20001; description = "Filebrowser port."; };
      linkwarden = lib.mkOption { type = lib.types.port; default = 3000; description = "Linkwarden port."; };
      open-webui = lib.mkOption { type = lib.types.port; default = 3080; description = "Open WebUI port."; };
      forgejo = lib.mkOption { type = lib.types.port; default = 3010; description = "Forgejo HTTP port."; };
      semaphore = lib.mkOption { type = lib.types.port; default = 3015; description = "Semaphore HTTP port."; };
      cockpit = lib.mkOption { type = lib.types.port; default = 9090; description = "Cockpit admin port."; };
      amp = lib.mkOption { type = lib.types.port; default = 8085; description = "AMP Web UI port."; };
      gatus = lib.mkOption { type = lib.types.port; default = 8084; description = "Gatus Web UI port."; };
      loki = lib.mkOption { type = lib.types.port; default = 3100; description = "Loki API port."; };
      grafana = lib.mkOption { type = lib.types.port; default = 3005; description = "Grafana Web UI port."; };
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
      # Verhindert Überlauf der EFI System-Partition (ESP) bei strengem 96MB Limit
      boot.loader.systemd-boot.configurationLimit = 5;
    })

    # ── KERNEL SLIMMING → modules/kernel-slim-q958.nix

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

          # Dynamisches Ressourcen-Management basierend auf RamGB
          max-jobs =
            if isLowRam then lib.mkForce 1
            else if isMidRam then lib.mkForce 2
            else lib.mkDefault 4;
          cores =
            if isLowRam then lib.mkForce 1
            else if isMidRam then lib.mkForce 2
            else lib.mkDefault 0;

          # Build-Timeout gegen hängende Prozesse
          timeout = 3600;
          max-silent-time = 600;

          experimental-features = [ "nix-command" "flakes" "auto-allocate-uids" "cgroups" ];
          sandbox = true;
          trusted-users = [ "root" config.my.configs.identity.user ];
        };

        # CPU & I/O Prioritäten für Builds (verhindert Host-Freezes)
        daemonCPUSchedPolicy = "idle";
        daemonIOSchedClass = "idle";
        daemonIOSchedPriority = 7;

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
  ];
}
