# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Impermanence, MergerFS, Restic, Storage-Mover zwischen Tiers
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#     - docs/guides/GUIDE-data-management.md
#   services:
#     - restic-backup
#   tags:
#     - storage
#     - impermanence
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.my.configs.identity.user;
  cfgImp = config.my.impermanence;
  cfgStorage = config.my.services.storage;
  cfgBackup = config.my.services.restic-backup;

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
  # Boot partition path for monitoring
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my = {
    impermanence = {
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

    services = {
      storage = {
        enable = lib.mkEnableOption "Hybrid MergerFS & ext4 pool pool config";
        poolMountPoint = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Shared virtual folder pool target (set in machines/<host>/profile.nix).";
        };
      };

      storage-mover = {
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

      restic-backup = {
        enable = lib.mkEnableOption "Restic offsite S3 backup schedule";
        healthcheckUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Dead Man's Switch heartbeat URL.";
        };
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── SOVEREIGN IMPERMANENCE (TMPFS /) ──────────────────────────────────────
    (lib.mkIf cfgImp.enable {
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
    })

    # ── MERGERFS HYBRID POOLING ───────────────────────────────────────────────
    (lib.mkIf cfgStorage.enable {
      boot.supportedFilesystems = [ "ext4" ];

      # Pooling mounts
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

      # Create parent mount points and temporary state dirs
      systemd = {
        tmpfiles.rules = [
          "d /mnt/tier-a 0775 root media -"
          "d /mnt/tier-b 0775 root media -"
          "d /mnt/tier-c 0775 root media -"
          "d /mnt/external 0775 root media -"
          "d /run/nixhome-pending-disks 0755 root root -"
        ];

        # ── PENDING DISKS WATCHER ───────────────────────────────────────────────
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
    })

    # ── RESTIC ENCRYPTED CLOUD SYNC ───────────────────────────────────────────
    (lib.mkIf cfgBackup.enable {
      services.restic.backups.tier-a-sovereign = {
        initialize = true;
        passwordFile = "/var/lib/secrets/restic_password";
        environmentFile = "/var/lib/secrets/restic_s3_creds";

        paths = [
          "${cfgImp.persistMountPoint}/var/lib/secrets"
          "${cfgImp.persistMountPoint}/var/lib/postgresql"
          "${cfgImp.persistMountPoint}/var/lib/vaultwarden"
          "${cfgImp.persistMountPoint}/var/lib/pocket-id"
          "${cfgImp.persistMountPoint}/var/lib/hass"
          "${cfgImp.persistMountPoint}/var/lib/zigbee2mqtt"
          "${cfgImp.persistMountPoint}/var/lib/paperless"
          "${cfgImp.persistMountPoint}/var/lib/linkwarden"
          "/home/${config.my.configs.identity.user}/.grok"
          "${cfgImp.persistMountPoint}/var/lib/grafana"
          "${cfgImp.persistMountPoint}/etc/nixos"
        ];

        exclude = [
          "**/MediaCover"
          "**/Backups"
          "**/cache/**"
          "**/logs/**"
          "/mnt/fast_pool/cache"
          "/var/cache/jellyfin"
        ];

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
        ];

        # Stop active database and application services to prevent write drift during backup
        backupPrepareCommand = ''
          echo "Stopping active web applications and database services..."
          systemctl stop paperless-web paperless-scheduler paperless-task-queue home-assistant linkwarden vaultwarden zigbee2mqtt || true
          systemctl stop mosquitto postgresql || true
        '';

        # Restart database and web applications after backup attempt finishes (even on failure)
        backupCleanupCommand = ''
          echo "Restarting database and web applications..."
          systemctl start postgresql mosquitto || true
          systemctl start paperless-web paperless-scheduler paperless-task-queue home-assistant linkwarden vaultwarden zigbee2mqtt || true
        '';
      };

      systemd.services.restic-backups-tier-a-sovereign = {
        postStop = lib.mkIf (cfgBackup.healthcheckUrl != "") ''
          status=$(${pkgs.systemd}/bin/systemctl show -p ExecMainStatus --value restic-backups-tier-a-sovereign.service 2>/dev/null || echo 1)
          if [ "$status" = "0" ]; then
            ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 "${cfgBackup.healthcheckUrl}"
          else
            ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 "${cfgBackup.healthcheckUrl}/fail" || true
          fi
        '';
      };
    })

    # ── PRECISION STORAGE CACHE MOVER ─────────────────────────────────────────
    (
      let
        cfgMover = config.my.services.storage-mover;
      in
      lib.mkIf cfgMover.enable {
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
      }
    )
  ];
}
