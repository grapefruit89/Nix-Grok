# ---
# meta:
#   layer: 3
#   role: module
#   purpose: MergerFS hybrid pool (Tier B/C/external) + pending disk watcher
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#   tags:
#     - storage
#     - mergerfs
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgStorage = config.my.services.storage;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.storage = {
    enable = lib.mkEnableOption "Hybrid MergerFS & ext4 pool config";
    poolMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Shared virtual folder pool target (set in machines/<host>/profile.nix).";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgStorage.enable {
    boot.supportedFilesystems = [ "ext4" ];

    fileSystems = {
      "/mnt/fast_pool" = {
        device = "mergerfs";
        fsType = "fuse.mergerfs";
        options = [
          "defaults"
          "allow_other"
          "minfreespace=10G"
          "category.create=mfs"
          "branches=/mnt/tier-b/*"
        ];
      };

      "${cfgStorage.poolMountPoint}" = {
        device = "mergerfs";
        fsType = "fuse.mergerfs";
        # category.create=epmfs: distributes files across Tier C drives
        # minfreespace=50G: avoids drive overflow
        # dropcacheonclose=true: enables fast HDD spindown via hd-idle
        options = [
          "defaults"
          "allow_other"
          "category.create=epmfs"
          "minfreespace=50G"
          "dropcacheonclose=true"
          "branches=/mnt/tier-c/*"
        ];
      };

      "/mnt/external_pool" = {
        device = "mergerfs";
        fsType = "fuse.mergerfs";
        options = [
          "defaults"
          "allow_other"
          "minfreespace=1G"
          "category.create=mfs"
          "branches=/mnt/external/*"
        ];
      };
    };

    # Setgid enforcing for media group (GID 169)
    users.groups.media.gid = config.my.groups.registry.media;

    systemd = {
      tmpfiles.rules = [
        "d /mnt/tier-a 0775 root media -"
        "d /mnt/tier-b 0775 root media -"
        "d /mnt/tier-c 0775 root media -"
        "d /mnt/external 0775 root media -"
        "d /run/nixhome-pending-disks 0755 root root -"
      ];

      # ── PENDING DISKS WATCHER ─────────────────────────────────────────────────
      services.nixhome-pending-watcher = {
        description = "Scans for new unlabelled legacy drives";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "pending-watcher" ''
            set -euo pipefail
            PENDING_DIR="/run/nixhome-pending-disks"
            mkdir -p "$PENDING_DIR"

            # Check raw disks using blkid
            for dev in /dev/sd*; do
              [ -b "$dev" ] || continue
              # If it has no filesystem label, mark it pending
              if ! ${pkgs.util-linux}/bin/blkid -o value -s LABEL "$dev" >/dev/null 2>&1; then
                echo "Unlabelled disk found: $dev"
                echo "PENDING:$dev:$(date -Iseconds)" > "$PENDING_DIR/$(basename "$dev").pending"
              fi
            done
          '';

          # Sandboxing & Hardening
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateNetwork = true;
          ReadWritePaths = [ "/run/nixhome-pending-disks" ];
          CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
        };
      };

      timers.nixhome-pending-watcher = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
          RandomizedDelaySec = "15";
        };
      };
    };
  };
}
