# ---
# meta:
#   layer: 3
#   role: module
#   purpose: HDD-freundliche Deferred-Deletion-Queue auf Tier B
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#   tags:
#     - storage
#     - deferred
#     - hdd
# ---
{ config, lib, pkgs, ... }:

let
  storage = config.my.configs.storage;
  tierCMount = storage.tierC.mountPoint;
in
{
  options.my.storage.deferred = {
    enable = lib.mkEnableOption "Deferred deletion queue (SSD staging, HDD-aware purge)";

    queueDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/fast_pool/delete_queue";
      description = "SSD queue directory for paths pending Tier-C deletion.";
    };

    maxAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Force delete queued paths after this many days even if HDDs are spun down.";
    };
  };

  config = lib.mkIf config.my.storage.deferred.enable (
    let
      cfg = config.my.storage.deferred;

      processScript = pkgs.writeShellScript "process-delete-queue" ''
    set -euo pipefail

    QUEUE_DIR="${cfg.queueDir}"
    MAX_AGE_DAYS=${toString cfg.maxAgeDays}
    HDD_POOL="${tierCMount}"

    mkdir -p "$QUEUE_DIR"

    ANY_ACTIVE=false
    for dev in \
      ${lib.concatStringsSep " \\\n      " (map (l: "/dev/disk/by-label/${l}") storage.tierC.labels)} \
      /dev/disk/by-label/TIER_C_* \
      /dev/disk/by-label/DISK_STORAGE_*; do
      [ -e "$dev" ] || continue
      if ${pkgs.hdparm}/bin/hdparm -C "$dev" 2>/dev/null | grep -q "active/idle"; then
        ANY_ACTIVE=true
        break
      fi
    done

    echo "deferred-delete: ANY_ACTIVE=$ANY_ACTIVE"

    if [ "$ANY_ACTIVE" = false ]; then
      OLDEST_AGE=$(${pkgs.findutils}/bin/find "$QUEUE_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1 || true)
      if [ -n "$OLDEST_AGE" ]; then
        MAX_AGE_SECONDS=$((MAX_AGE_DAYS * 86400))
        CURRENT_TIME=$(date +%s)
        OLDEST_AGE_INT=''${OLDEST_AGE%.*}
        if [ $((CURRENT_TIME - OLDEST_AGE_INT)) -lt "$MAX_AGE_SECONDS" ]; then
          echo "deferred-delete: HDD standby, queue younger than ${toString cfg.maxAgeDays}d — skip"
          exit 0
        fi
      else
        exit 0
      fi
    fi

    shopt -s nullglob
    for ENTRY in "$QUEUE_DIR"/*; do
      [ -f "$ENTRY" ] || continue
      [ -s "$ENTRY" ] || { rm -f -- "$ENTRY"; continue; }

      FILE_AGE_SECONDS=$(($(date +%s) - $(stat -c %Y "$ENTRY")))
      MAX_AGE_SECONDS=$((MAX_AGE_DAYS * 86400))

      SHOULD_DELETE=false
      if [ "$ANY_ACTIVE" = true ]; then
        SHOULD_DELETE=true
      elif [ "$FILE_AGE_SECONDS" -gt "$MAX_AGE_SECONDS" ]; then
        SHOULD_DELETE=true
        echo "deferred-delete: forcing aged entry $ENTRY"
      fi

      if [ "$SHOULD_DELETE" = true ]; then
        TARGET_PATH=$(cat -- "$ENTRY")
        if [ -n "$TARGET_PATH" ] && [ -e "$TARGET_PATH" ]; then
          REAL_TARGET=$(readlink -f -- "$TARGET_PATH" || echo "$TARGET_PATH")
          if [[ "$REAL_TARGET" == "$HDD_POOL"* ]] || [[ "$REAL_TARGET" == /mnt/tier-c/* ]]; then
            echo "deferred-delete: removing $REAL_TARGET"
            rm -rf -- "$REAL_TARGET"
          else
            echo "deferred-delete: SECURITY — out-of-bounds target $REAL_TARGET"
            exit 1
          fi
        fi
        rm -f -- "$ENTRY"
      fi
    done
      '';

      deferDeleteBin = pkgs.writeShellScriptBin "nixhome-defer-delete" ''
    set -euo pipefail
    if [ $# -lt 1 ]; then
      echo "Usage: nixhome-defer-delete <path-on-tier-c>" >&2
      exit 1
    fi
    QUEUE_DIR="${cfg.queueDir}"
    mkdir -p "$QUEUE_DIR"
    TARGET=$(readlink -f -- "$1")
    STAMP=$(date +%s)
    BASENAME=$(basename "$TARGET")
    echo "$TARGET" > "$QUEUE_DIR/''${STAMP}-''${BASENAME}.queue"
        echo "Queued for deferred delete: $TARGET"
      '';
    in
    {
      environment.systemPackages = [ deferDeleteBin ];

    systemd.services.process-delete-queue = {
      description = "Process deferred Tier-C deletion queue";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = processScript;
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          tierCMount
          "/mnt/tier-c"
          cfg.queueDir
        ];
        InaccessiblePaths = [ "/home" "/etc/ssh" ];
      };
    };

    systemd.timers.process-delete-queue = {
      description = "Hourly deferred deletion queue processor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };

      systemd.tmpfiles.rules = [
        "d ${cfg.queueDir} 0755 root root -"
      ];
    }
  );
}