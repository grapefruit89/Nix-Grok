# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Sovereign Impermanence (ephemeral tmpfs root + Tier-A persistent bind mounts)
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#     - docs/guides/GUIDE-data-management.md
#   tags:
#     - storage
#     - impermanence
# ---
{
  config,
  lib,
  ...
}:
let
  user = config.my.configs.identity.user;
  cfgImp = config.my.impermanence;

  # Tier A (NVMe/SSD Cache): Persistent high-priority states
  tierAStatic = {
    paths = [
      "/var/lib/secrets"
      "/var/lib/nixos"
      "/etc/nixos"
      "/var/lib/netbird"
      "/var/lib/postgresql"
      "/var/lib/caddy"
      "/var/lib/loki"
      "/var/lib/grafana"
      "/var/lib/gatus"
      "/var/lib/crowdsec"
    ]
    ++ lib.optional (user != "") "/home/${user}/.grok";
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key"
    ];
  };

  # Journald persistent storage (forensics and crash debugging)
  journaldPath = "/var/log/journal";

  # Tier B (SSD Pool): Speed-sensitive volatile caches and incomplete downloads
  tierB = {
    paths = [
      "/mnt/fast_pool/cache"
      "/mnt/fast_pool/downloads"
      "/var/cache"
    ];
  };
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.impermanence = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.mode == "production";
      description = "Sovereign Impermanence (ephemeral tmpfs root)";
    };
    persistentDisk = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Persistent block device (set in machines/<host>/profile.nix).";
    };
    persistMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Persistent mount point (set in machines/<host>/profile.nix).";
    };
    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Zusätzliche Tier-A-Pfade aus mkService persistDirs.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgImp.enable {
    # Stateless root on RAM (tmpfs) & persistent storage partition & declarative bind mounts
    fileSystems = {
      "/" = lib.mkForce {
        device = "none";
        fsType = "tmpfs";
        options = [
          "defaults"
          "size=16G"
          "mode=755"
        ];
      };

      "${cfgImp.persistMountPoint}" = {
        device = cfgImp.persistentDisk;
        fsType = "ext4";
        neededForBoot = true;
      };
    }
    // lib.listToAttrs (
      map (path: {
        name = path;
        value = {
          device = "${cfgImp.persistMountPoint}${path}";
          fsType = "none";
          options = [ "bind" ];
          depends = [ cfgImp.persistMountPoint ];
        };
      }) (tierAStatic.paths ++ config.my.impermanence.extraPaths)
    )
    // lib.listToAttrs (
      map (file: {
        name = file;
        value = {
          device = "${cfgImp.persistMountPoint}${file}";
          fsType = "none";
          options = [ "bind" ];
          depends = [ cfgImp.persistMountPoint ];
        };
      }) tierAStatic.files
    )
    // {
      "${journaldPath}" = {
        device = "${cfgImp.persistMountPoint}${journaldPath}";
        fsType = "none";
        options = [ "bind" ];
        depends = [ cfgImp.persistMountPoint ];
      };
    };

    # Journald persistent storage for forensics
    services.journald = {
      extraConfig = ''
        Storage=persistent
        SystemMaxUse=1G
        RuntimeMaxUse=100M
        MaxRetentionSec=1month
      '';
    };

    systemd.tmpfiles.rules =
      (map (p: "d ${cfgImp.persistMountPoint}${p} 0755 root root -") (
        tierAStatic.paths ++ config.my.impermanence.extraPaths
      ))
      ++ (map (p: "d ${p} 0755 root root -") tierB.paths)
      ++ [ "d ${cfgImp.persistMountPoint}${journaldPath} 0755 root root -" ];
  };
}
