# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Boot-Safeguard, Nix-Tuning, ZRAM-Swap, Locale, zentrale System-Optionen
#   docs:
#     - docs/adr/013-flake-portability.md
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
  cfgJournald = config.my.core.journald;

  ramGB = config.my.configs.hardware.ramGB;
  nixStoreGB = config.my.configs.hardware.nixStoreGB;
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
      boot-safeguard.configurationLimit = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = ''
          Maximale Anzahl NixOS-Generationen im EFI-Bootloader-Menü.
          Schützt die ESP-Partition vor Überlauf — jede Generation belegt ~15–50 MB
          (Kernel + Initrd + Bootloader-Eintrag). q958: 1 GB ESP (NIXBOOT), default 5 konservativ.
          Auf Maschinen mit kleiner ESP (256–512 MB) auf 3 senken.
        '';
      };
      journald.maxUse = lib.mkOption {
        type = lib.types.str;
        default = "500M";
        description = ''
          Maximale Journal-Größe (SystemMaxUse). Verhindert unbegrenztes Wachstum von
          /var/log/journal ohne Impermanence. 500M = ausreichend für Debugging auf kleinen SSDs.
          Auf Systemen mit viel Disk (≥ 500 GB) kann dieser Wert auf 1–2G erhöht werden.
        '';
      };
      journald.maxRetention = lib.mkOption {
        type = lib.types.str;
        default = "90day";
        description = "Maximale Journal-Retention (MaxRetentionSec). 90 Tage für Incident-Analyse; auf Impermanence irrelevant.";
      };
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
      # kernel-slim Option lebt jetzt nur noch in modules/20-security/25-kernel-policy.nix (Duplikat entfernt)
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
        nixStoreGB = lib.mkOption {
          type = lib.types.int;
          description = "Nix-Store-Partition-Größe in GB — bestimmt GC-Trigger (min-free/max-free).";
        };
      };
      server = {
        lanIP = lib.mkOption {
          type = lib.types.str;
          description = "Server LAN IP (set in machines/<host>/profile.nix).";
        };
        netbirdIP = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Server Netbird IP (nach 'netbird up' mit 'netbird status' ermitteln und in profile.nix eintragen).";
        };
      };
      network = {
        dnsBootstrap = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                ip = lib.mkOption {
                  type = lib.types.str;
                  description = "Server-IP.";
                };
                hostname = lib.mkOption {
                  type = lib.types.str;
                  description = "TLS-Hostname fuer SNI.";
                };
              };
            }
          );
          default = [
            {
              ip = "1.1.1.1";
              hostname = "cloudflare-dns.com";
            }
            {
              ip = "9.9.9.9";
              hostname = "dns.quad9.net";
            }
            {
              ip = "149.112.112.112";
              hostname = "dns.quad9.net";
            }
          ];
          description = "DoT-Nameserver — Single Source of Truth für resolved + Technitium-Forwarder. Niemals Klartext-IP.";
        };
        ipv6 = {
          disableOnInterfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Physische Interfaces ohne IPv6 (sysctl + systemd-networkd). Netbird/WG nicht listen.";
          };
          firewall = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "false = keine CrowdSec/nftables IPv6-Regeln (Homelab nur v4 auf LAN).";
          };
        };
      };
    };

    # my.ports.* → 08-ports.nix
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

      # Journal-Größe begrenzen (ohne Impermanence wächst /var/log/journal unbegrenzt).
      # Werte konfigurierbar via my.core.journald.maxUse + .maxRetention.
      services.journald.extraConfig = lib.mkDefault ''
        SystemMaxUse=${cfgJournald.maxUse}
        MaxRetentionSec=${cfgJournald.maxRetention}
      '';
    }

    # ── BOOT SAFEGUARD ────────────────────────────────────────────────────────
    (lib.mkIf cfgBoot.enable {
      boot.loader.systemd-boot.configurationLimit = cfgBoot.configurationLimit;
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

          # Automatische Store-Optimierung + Notfall-GC bei Platzmangel
          auto-optimise-store = true;
          builders-use-substitutes = true;
          fallback = true;
          # GC-Trigger: 1% des Stores → GC auslösen; 2% → GC-Ziel.
          # Abgeleitet aus my.configs.hardware.nixStoreGB (profile.nix) — skaliert mit jeder Maschine.
          # q958 (468 GB): min ≈ 4.7 GB, max ≈ 9.4 GB.
          min-free = nixStoreGB * 1073741824 / 100;
          max-free = nixStoreGB * 1073741824 / 50;

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

          # 1h timeout: hängende Builds (häufig bei Cross-Compile oder Fetcher-Deadlock).
          # 10min max-silent-time: Build ohne stdout → hängt wahrscheinlich in IO/Network.
          timeout = 3600;
          max-silent-time = 600;

          experimental-features = [
            "nix-command"
            "flakes"
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
        # ── Nix-Entwicklungs-Werkzeuge ────────────────────────────────────────
        nix-tree # Abhängigkeitsgraph visualisieren: nix-tree /nix/store/<drv>
        nix-diff # Store-Path-Diff: nix-diff /nix/store/old /nix/store/new
        nix-output-monitor # Schönerer nix-Build-Output (intern von nh genutzt)
        nix-du # Disk-Usage im Nix-Store: nix-du -s
        noogle-search # Interaktive fzf-Suche über Nix builtins + lib.*-Funktionen
        fzf # Fuzzy-Finder (Basis für noogle-search + shell history)
        # Pflicht-Trio (POL-FMT-010..012): nixfmt + statix + deadnix
        # alejandra und nixpkgs-fmt sind per Assertion verboten (lib/forbidden-tech.nix)
        nixfmt
        statix
        deadnix
        pre-commit

        # ── Moderne CLI-Tools (ersetzt klassische POSIX-Befehle) ──────────────
        nh # nixos-rebuild UX-Wrapper (menschliche Rebuilds; Dry-Build-Gate bleibt scripts/nixos-rebuild-safe.sh)
        nvd # Diff-Ausgabe nach nixos-rebuild switch
        bat # cat-Ersatz mit Syntax-Highlighting
        eza # ls-Ersatz mit Git-Status + Icons
        fd # find-Ersatz (schneller, intuitivere Syntax)
        ripgrep # grep-Ersatz (schneller, .gitignore-aware)
        btop # top-Ersatz (moderne UI)
        dust # du-Ersatz (Baumansicht)
        duf # df-Ersatz (schöner Output)
      ];

      # Moderne Shell-Aliases: NUR für interaktive Shells (nicht für Skripte/Aktivierungen)
      programs.bash.shellAliases = {
        cat = "bat --paging=never";
        ls = "eza --icons --git";
        ll = "eza --icons --git -la";
        tree = "eza --tree --icons --git";
        find = "fd";
        grep = "rg";
        du = "dust";
        df = "duf";
        top = "btop";
        noogle = "noogle-search"; # Nix lib.*-Funktionen + builtins interaktiv suchen
        # NixOS Rebuild-Workflow (immer via Safe-Script — dry-build + tmux-Pflicht)
        nsw = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch";
        ntest = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test";
        nup = "cd /etc/nixos && nix flake update";
        nclean = "sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +5 && sudo nix-store --gc";
      };

      # fzf Shell-Integration: Ctrl+R History-Suche + Ctrl+T Datei-Picker
      programs.fzf = {
        fuzzyCompletion = true;
        keybindings = true;
      };
    })

    # ── PRE-COMMIT HOOKS (nur development) ───────────────────────────────────
    # .git/hooks/ liegt außerhalb des Nix-Store — activationScript ist der idiomatische
    # Escape-Hatch um POL-FMT-010..012 (nixfmt/statix/deadnix) nach jedem switch
    # automatisch durchzusetzen. Nur in my.mode == "development" sinnvoll;
    # Produktionsserver haben kein /etc/nixos/.git und keinen Dev-Workflow.
    (lib.mkIf (cfgNix.enable && config.my.mode == "development") {
      system.activationScripts.preCommitInstall = {
        deps = [ ];
        text = ''
          if [ -d /etc/nixos/.git ]; then
            ${pkgs.pre-commit}/bin/pre-commit install \
              --git-dir /etc/nixos/.git \
              --work-tree /etc/nixos \
              --config /etc/nixos/.pre-commit-config.yaml \
              2>/dev/null || true
          fi
        '';
      };
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

      # Kernel-Parameter für aggressives und effizientes ZRAM-Paging.
      # Quellen: kernel.org ZRAM-Doku + systemd/zram-generator-Empfehlungen.
      boot.kernel.sysctl = {
        # ZRAM-Bereich (0-200): 180 signalisiert dem Kernel, RAM aggressiv in das
        # schnelle komprimierte ZRAM auszulagern statt gar nicht zu swappen.
        # Default (60) ist für langsame Disk-Swap gedacht — auf ZRAM (RAM-Geschwindigkeit)
        # ist Swapping praktisch kostenlos, daher hoher Wert sinnvoll.
        "vm.swappiness" = lib.mkForce 180;
        # ZRAM braucht kein Read-Ahead: einzelne komprimierte Pages werden direkt
        # gelesen. Read-Ahead würde nur unnötig Bandbreite verschwenden.
        "vm.page-cluster" = lib.mkDefault 0;
        # >100 = Kernel gibt VFS-Caches (Dentries/Inodes) schneller frei → mehr RAM
        # für Anwendungen und ZRAM-komprimierte Pages. Sinnvoll auf RAM-beschränkten Systemen.
        "vm.vfs_cache_pressure" = lib.mkDefault 150;
      };
    })
  ];
}
