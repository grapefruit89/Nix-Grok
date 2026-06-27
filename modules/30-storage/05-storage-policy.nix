# ---
# meta:
#   id: NIXH-05-MOD-002
#   layer: 3
#   role: module
#   purpose: Tier-C-Exclusion — Build-time Assertion gegen HDD-Zugriffe in systemd
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - AGENTS.md
#   lib:
#     - lib/storage-policy.nix
#   tags:
#     - storage
#     - tier-c
# ---
{
  config,
  lib,
  ...
}: let
  policy = import ../../lib/storage-policy.nix {inherit lib;};
  storage = config.my.configs.storage;
  inherit (storage) tierC;

  defaultExemptions = [
    # Mover & Automount
    "nixhome-storage-mover"
    "nixhome-pending-watcher"
    "process-delete-queue"
    "storage-automount"
    # Usenet / Cold paths
    "sabnzbd"
    # Media read-only auf HDD/MergerFS
    "jellyfin"
    "audiobookshelf"
    "sonarr"
    "radarr"
    "readarr"
    "prowlarr"
    # Backup darf NIXBACKUP
    "restic-backups-tier-a-sovereign"
  ];

  markers = policy.defaultTierCMarkers {
    inherit (tierC) mountPoint;
    inherit (tierC) automountParent;
    inherit (tierC) labels;
    inherit (tierC) legacyPrefixes;
  };
in {
  options.my.configs.storage = {
    tierB.mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/fast_pool";
      description = "Tier B SSD pool mount (SATA only).";
    };
    tierC = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/media";
        description = "Tier C cold media pool (HDD / MergerFS).";
      };
      automountParent = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/tier-c";
        description = "Parent directory for per-disk Tier C automounts.";
      };
      labels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "NIXMEDIA"
          "NIXBACKUP"
        ];
      };
      legacyPrefixes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["TIER_C_"];
        description = "Legacy path prefixes that imply Tier C.";
      };
    };
  };

  options.my.storage-policy = {
    enable = lib.mkEnableOption "Tier-C exclusion assertions (HDD only for whitelisted services)";
    tierCExemptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultExemptions;
      description = "systemd unit names (ohne .service) die Tier C berühren dürfen.";
    };
  };

  config =
    {
      my.storage-policy.enable = lib.mkDefault true;
    }
    // lib.mkIf config.my.storage-policy.enable {
      assertions = [
        (policy.mkTierCAssertion {
          exemptions = config.my.storage-policy.tierCExemptions;
          inherit markers;
          systemdServices = config.systemd.services;
        })
      ];
    };
}
