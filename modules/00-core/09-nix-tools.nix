# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Nix-Store-Tuning, Dev-Tools (bat/eza/rg…), Shell-Aliases, Pre-Commit, ZRAM-Swap
#   tags:
#     - nix
#     - developer-experience
#     - zram
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgNix = config.my.core.nix-tuning;
  cfgZram = config.my.core.zram-swap;
  ramGB = config.my.configs.hardware.ramGB;
  nixStoreGB = config.my.configs.hardware.nixStoreGB;
  isLowRam = ramGB <= 4;
  isMidRam = ramGB > 4 && ramGB <= 8;
in
{
  config = lib.mkMerge [
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
        # NixOS Rebuild-Workflow — immer via Safe-Script (dry-build-Gate + Log nach /tmp/nixos-switch.log)
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
