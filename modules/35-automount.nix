# 35-automount.nix – Label-basiertes Tier-Mounting
# Regeln:
#   Tier A/B = SSD only (rotational=0), nie HDD
#   Tier A   = NVMe-SSD, oder SATA-SSD wenn keine NVMe (unlabeled: nvme → A, ata → B)
#   Tier B   = SATA-SSD only — nie NVMe, nie HDD
#   Tier C   = HDD only (rotational=1, cold storage)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.storage-automount;
  mediaGroup = "media";
  tierCLabelMatch = lib.concatMapStringsSep " || " (l: "[ \"\$LABEL\" = \"${l}\" ]") cfg.tierCLabels;
in
{
  options.my.services.storage-automount = {
    enable = lib.mkEnableOption "Automated storage auto-mounting and pooling with Tier A/B/C";

    singleDisk = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Host hat nur eine interne System-SSD (Tier A); keine Auto-Tier-Zuweisung für Systemplatte.";
    };

    tierADevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Block device der Tier-A-Systemplatte (z. B. /dev/sda), set in machines/<host>/profile.nix.";
    };

    systemLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "NIXBOOT"
        "BOOT"
        "NIXPERSIST"
        "NIXHOME_PERSIST"
        "NIXSTORE"
        "CRYPTROOT"
      ];
      description = "Partition-Labels die fest in hardware.nix gemountet sind — Automount überspringt diese.";
    };

    tierBLabel = lib.mkOption {
      type = lib.types.str;
      default = "NIXDATA";
      description = "Label für Tier-B-SSD (fast pool branch).";
    };

    tierCLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "NIXMEDIA"
        "NIXBACKUP"
      ];
      description = "Labels für Tier-C-HDD (cold storage / media pool branches).";
    };

    defaultTierForInternalHDD = lib.mkOption {
      type = lib.types.enum [ "C" ];
      default = "C";
      description = "Tier für interne HDDs ohne Label — immer C (cold storage).";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.media.gid = 169;

    services.udev.extraRules = ''
      SUBSYSTEM=="block", ACTION=="add", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="?*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nixhome-automount@%k.service"
      SUBSYSTEM=="block", ACTION=="remove", ENV{DEVTYPE}=="partition", RUN+="${pkgs.systemd}/bin/systemctl stop nixhome-automount@%k.service"
    '';

    systemd.services."nixhome-automount@" = {
      description = "NixHome Tiered Automounter for device %I";
      path = with pkgs; [
        util-linux
        udev
        gnugrep
        coreutils
        systemd
        procps
        psmisc
      ];

      bindsTo = [ "dev-%i.device" ];
      after = [
        "dev-%i.device"
        "local-fs.target"
      ];
      requires = [ "dev-%i.device" ];
      partOf = [ "dev-%i.device" ];

      unitConfig = {
        StopWhenUnneeded = true;
        CollectMode = "inactive-or-failed";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        CapabilityBoundingSet = [
          "CAP_SYS_ADMIN"
          "CAP_CHOWN"
          "CAP_FOWNER"
          "CAP_DAC_OVERRIDE"
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateNetwork = true;
        ReadWritePaths = [ "/mnt" ];

        ExecStart = pkgs.writeShellScript "tiered-automount" ''
          DEV="/dev/%I"
          if [ ! -b "$DEV" ]; then
            echo "Device $DEV is not a valid block device. Exiting."
            exit 0
          fi

          LABEL=$(blkid -o value -s LABEL "$DEV" | sed 's/[^a-zA-Z0-9_-]/_/g' || true)
          UUID=$(blkid -o value -s UUID "$DEV" || true)
          if [ -z "$UUID" ]; then
            echo "No UUID found for $DEV. Cannot mount safely. Exiting."
            exit 0
          fi
          [ -n "$LABEL" ] || LABEL="disk-$UUID"

          for SYS_LABEL in ${lib.concatStringsSep " " (map (l: "\"${l}\"") cfg.systemLabels)}; do
            if [ "$LABEL" = "$SYS_LABEL" ]; then
              echo "System partition label $LABEL — skip automount."
              exit 0
            fi
          done

          BUS=$(udevadm info --query=property --name="$DEV" | grep "ID_BUS=" | cut -d= -f2 || true)

          DISK_NAME="%I"
          if [[ "$DISK_NAME" =~ ^nvme ]]; then
            DISK_NAME=$(echo "$DISK_NAME" | sed 's/p[0-9]*$//')
          else
            DISK_NAME=$(echo "$DISK_NAME" | sed 's/[0-9]*$//')
          fi

          if ${if cfg.singleDisk then "true" else "false"} && [ -n "${cfg.tierADevice}" ]; then
            TIER_A_BASE=$(basename "${cfg.tierADevice}")
            if [ "$DISK_NAME" = "$TIER_A_BASE" ]; then
              echo "Tier-A system disk ($TIER_A_BASE) — skip automount."
              exit 0
            fi
          fi

          ROTATIONAL="1"
          if [ -f "/sys/block/$DISK_NAME/queue/rotational" ]; then
            ROTATIONAL=$(cat "/sys/block/$DISK_NAME/queue/rotational")
          fi

          SIZE_SECTORS="0"
          if [ -f "/sys/block/$DISK_NAME/size" ]; then
            SIZE_SECTORS=$(cat "/sys/block/$DISK_NAME/size")
          fi
          SIZE_GB=$((SIZE_SECTORS * 512 / 1000000000))

          enforce_tier_rules() {
            local tier="$1"
            if [ "$tier" = "INT_C" ] && [ "$ROTATIONAL" = "0" ]; then
              echo "REJECT: Tier C (cold storage) requires HDD (rotational=1), device is SSD."
              exit 0
            fi
            if { [ "$tier" = "INT_A" ] || [ "$tier" = "INT_B" ]; } && [ "$ROTATIONAL" = "1" ]; then
              echo "REJECT: Tier A/B require SSD (rotational=0), device is HDD."
              exit 0
            fi
            if [ "$tier" = "INT_B" ] && { [ "$BUS" = "nvme" ] || [[ "$DISK_NAME" =~ ^nvme ]]; }; then
              echo "REJECT: Tier B requires SATA SSD — NVMe not allowed."
              exit 0
            fi
          }

          # ---- Klassifikation ----
          if [ "$BUS" = "usb" ]; then
            if [[ "$LABEL" =~ ^EXT_SSD_ ]]; then
              TIER="EXT_SSD"
              MOUNT_BASE="/mnt/external/ssd"
            elif [[ "$LABEL" =~ ^EXT_HDD_ ]]; then
              TIER="EXT_HDD"
              MOUNT_BASE="/mnt/external/hdd"
            elif [[ "$LABEL" =~ ^EXT_USB_ ]]; then
              TIER="EXT_USB"
              MOUNT_BASE="/mnt/external/usb"
            else
              if [ "$ROTATIONAL" = "0" ]; then
                if [ "$SIZE_GB" -gt 128 ]; then
                  TIER="EXT_SSD"
                  MOUNT_BASE="/mnt/external/ssd"
                else
                  TIER="EXT_USB"
                  MOUNT_BASE="/mnt/external/usb"
                fi
              else
                TIER="EXT_HDD"
                MOUNT_BASE="/mnt/external/hdd"
              fi
            fi
            MOUNT_DIR="$MOUNT_BASE-$LABEL"
            USE_POOL="external_pool"

          else
            if [[ "$LABEL" =~ ^TIER_A_ ]] || [ "$LABEL" = "NIXPERSIST" ] || [ "$LABEL" = "NIXSTORE" ]; then
              TIER="INT_A"
              MOUNT_DIR="/mnt/tier-a/$LABEL"
              USE_POOL="none"
            elif [[ "$LABEL" =~ ^TIER_B_ ]] || [ "$LABEL" = "${cfg.tierBLabel}" ]; then
              TIER="INT_B"
              MOUNT_DIR="/mnt/tier-b/$LABEL"
              USE_POOL="fast_pool"
            elif [[ "$LABEL" =~ ^TIER_C_ ]] || [[ "$LABEL" =~ ^DISK_STORAGE_ ]] \
              || ${if tierCLabelMatch != "" then tierCLabelMatch else "false"}; then
              TIER="INT_C"
              MOUNT_DIR="/mnt/tier-c/$LABEL"
              USE_POOL="media_pool"
            else
              if [ "$ROTATIONAL" = "0" ]; then
                if { [ "$BUS" = "nvme" ] || [[ "$DISK_NAME" =~ ^nvme ]]; }; then
                  TIER="INT_A"
                  MOUNT_DIR="/mnt/tier-a/auto-$LABEL"
                  USE_POOL="none"
                elif [ "$BUS" = "ata" ]; then
                  TIER="INT_B"
                  MOUNT_DIR="/mnt/tier-b/auto-$LABEL"
                  USE_POOL="fast_pool"
                else
                  echo "REJECT: Unlabeled internal SSD with unknown bus ($BUS) — label as NIXDATA or TIER_B_*."
                  exit 0
                fi
              else
                TIER="INT_C"
                MOUNT_DIR="/mnt/tier-c/auto-$LABEL"
                USE_POOL="media_pool"
              fi
            fi
          fi

          enforce_tier_rules "$TIER"

          if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
            echo "Mountpoint $MOUNT_DIR is already mounted. Skipping."
            exit 0
          fi

          echo "Mounting $DEV as $TIER (rotational=$ROTATIONAL) → $MOUNT_DIR"
          mkdir -p "$MOUNT_DIR"

          FSTYPE=$(blkid -o value -s TYPE "$DEV" || true)
          case "$FSTYPE" in
            btrfs)   mount -o noatime,compress=zstd,nofail "$DEV" "$MOUNT_DIR" ;;
            ext4)    mount -o noatime,nofail "$DEV" "$MOUNT_DIR" ;;
            ntfs|exfat|vfat)
                     mount -o noatime,utf8,nofail "$DEV" "$MOUNT_DIR" || \
                     mount -o noatime,nofail "$DEV" "$MOUNT_DIR" ;;
            *)       echo "Unsupported FS: $FSTYPE. Trying raw mount..."; mount -o noatime,nofail "$DEV" "$MOUNT_DIR" ;;
          esac

          chown -R root:${mediaGroup} "$MOUNT_DIR" 2>/dev/null || true
          chmod -R 775 "$MOUNT_DIR" 2>/dev/null || true
          find "$MOUNT_DIR" -type d -exec chmod g+s {} + 2>/dev/null || true

          if [ "$USE_POOL" != "none" ]; then
            echo "Signalling MergerFS to refresh pool: $USE_POOL"
            killall -SIGHUP mergerfs || true
          fi
        '';

        ExecStop = pkgs.writeShellScript "tiered-autounmount" ''
          DEV="/dev/%I"
          MNT_PATHS=$(mount | grep "^$DEV " | cut -d' ' -f3 || true)
          for p in $MNT_PATHS; do
            echo "Unmounting path: $p..."
            umount -l "$p" 2>/dev/null && rmdir "$p" 2>/dev/null
          done
          killall -SIGHUP mergerfs || true
        '';
      };
    };
  };
}
