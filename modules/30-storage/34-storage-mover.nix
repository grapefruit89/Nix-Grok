# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Precision Storage Cache Mover (rclone local engine, SSD→HDD hysteresis)
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#   tags:
#     - storage
#     - mover
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgMover = config.my.services.storage-mover;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.storage-mover = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.services.storage.enable;
      description = "Enable Precision Storage Cache Mover (rclone local engine).";
    };
    sourceDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SSD cache source directory (set in machines/<host>/profile.nix).";
    };
    targetDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "HDD pool target directory (set in machines/<host>/profile.nix).";
    };
    minAge = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Minimum file age before migration (rclone format, e.g., 30d).";
    };
    capacityThreshold = lib.mkOption {
      type = lib.types.int;
      default = 85;
      description = "Cache disk capacity percentage that forces migration regardless of HDD state.";
    };
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:00:00";
      description = "Execution cron-style trigger interval.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgMover.enable {
    systemd.services.nixhome-storage-mover = {
      description = "Precision Storage Cache Mover (rclone local engine)";
      after = [
        "local-fs.target"
        "network.target"
      ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "storage-mover" ''
          set -euo pipefail

          # Check current SSD cache capacity
          CACHE_USAGE=$(df -h "${cfgMover.sourceDir}" | awk 'NR==2 {print $5}' | sed 's/%//')

          # Helper to check if any of our storage disks are already spinning
          disks_spinning=false
          for dev in /dev/disk/by-label/DISK_STORAGE_* /dev/disk/by-label/TIER_C_*; do
            if [ -e "$dev" ]; then
              # hdparm -C returns 0 if active/idle, non-zero if standby/spun down
              if ${pkgs.hdparm}/bin/hdparm -C "$dev" 2>/dev/null | grep -q "active/idle"; then
                disks_spinning=true
                break
              fi
            fi
          done

          # Hysteresis controller decision logic
          if [ "$CACHE_USAGE" -ge "${toString cfgMover.capacityThreshold}" ]; then
            echo "SSD Cache usage critical ($CACHE_USAGE%). Forcing migration to HDDs..."
          elif [ "$disks_spinning" = true ]; then
            echo "HDDs are already spinning ($CACHE_USAGE% SSD usage). Performing opportunistic migration..."
          else
            echo "HDDs are spun down and SSD usage ($CACHE_USAGE%) is under threshold (${toString cfgMover.capacityThreshold}%). Sleeping to conserve power."
            exit 0
          fi

          # Perform the atomic, verified local-to-local move via rclone
          echo "Starting local file migration from ${cfgMover.sourceDir} to ${cfgMover.targetDir}..."
          ${pkgs.rclone}/bin/rclone move "${cfgMover.sourceDir}" "${cfgMover.targetDir}" \
            --min-age "${cfgMover.minAge}" \
            --delete-empty-src-dirs \
            --transfers=4 \
            --checkers=8 \
            --exclude "**/incomplete/**" \
            --exclude "**/.staging/**" \
            --exclude "**/*.wal" \
            --exclude "**/*.shm" \
            --exclude "**/*.journal" \
            -v \
            --log-file=/var/log/rclone-mover.log

          # Apply GID 169 Setgid inheritance on target directories to avoid permission drift
          echo "Applying media group permissions to target directories..."
          find "${cfgMover.targetDir}" -type d -exec chmod g+s {} + || true
          chown -R root:media "${cfgMover.targetDir}" || true
          chmod -R 775 "${cfgMover.targetDir}" || true
        '';

        # Härtung & Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_FOWNER"
          "CAP_DAC_OVERRIDE"
        ];
        ReadWritePaths = [
          cfgMover.sourceDir
          cfgMover.targetDir
          "/var/log"
        ];
      };
    };

    systemd.timers.nixhome-storage-mover = {
      description = "Precision Storage Cache Mover Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfgMover.onCalendar;
        Persistent = true;
      };
    };
  };
}
