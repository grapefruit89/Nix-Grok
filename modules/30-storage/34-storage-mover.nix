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

  tierCDevPaths = lib.concatStringsSep " " (
    map (l: "/dev/disk/by-label/${l}") config.my.services.storage-automount.tierCLabels
  );

  excludeFlags = lib.concatMapStringsSep " \\\n            " (p: "--exclude \"${p}\"") (
    [
      "**/incomplete/**"
      "**/.staging/**"
      "**/*.wal"
      "**/*.shm"
      "**/*.journal"
    ]
    ++ cfgMover.extraExcludes
  );
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
      description = "OnCalendar — bewusst zeitbasiert: Mover-Fenster wenn HDD ggf. spun up; kein lokales Event-Äquivalent für Kapazitäts-Schwellwert im Idle.";
    };
    rcloneTransfers = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "rclone --transfers: parallele Datei-Kopiervorgänge.";
    };
    rcloneCheckers = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "rclone --checkers: parallele Prüfsummen-Worker.";
    };
    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Zusätzliche rclone --exclude-Muster, werden an die Built-in-Liste angehängt.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgMover.enable {
    assertions = [
      {
        assertion = cfgMover.sourceDir != "";
        message = "my.services.storage-mover.sourceDir muss gesetzt sein (z. B. in machines/<host>/default.nix).";
      }
      {
        assertion = cfgMover.targetDir != "";
        message = "my.services.storage-mover.targetDir muss gesetzt sein (z. B. in machines/<host>/default.nix).";
      }
    ];

    systemd.services.nixhome-storage-mover = {
      description = "Precision Storage Cache Mover (rclone local engine)";
      after = [ "local-fs.target" ];

      # Systemd-native guards: überspringen statt scheitern wenn Pool nicht gemountet.
      # lib.dirOf: "/mnt/fast_pool/downloads" → "/mnt/fast_pool" (der echte Mountpoint).
      unitConfig.ConditionPathIsMountPoint = [
        (lib.dirOf cfgMover.sourceDir)
        (lib.dirOf cfgMover.targetDir)
      ];

      serviceConfig = {
        Type = "oneshot";
        # Daten-Migration kann Stunden dauern — kein Start-Timeout.
        TimeoutStartSec = "infinity";

        ExecStart = pkgs.writeShellScript "storage-mover" ''
          set -euo pipefail

          # SSD-Cache-Auslastung: --output=pcent → eine Spalte, kein awk/sed nötig
          CACHE_USAGE=$(df --output=pcent "${cfgMover.sourceDir}" | tail -1 | tr -d ' %')

          # Prüfen ob Tier-C-HDDs bereits drehen (CAP_SYS_RAWIO → HDIO_DRIVE_CMD ioctl)
          disks_spinning=false
          shopt -s nullglob
          for dev in ${tierCDevPaths} /dev/disk/by-label/TIER_C_* /dev/disk/by-label/DISK_STORAGE_*; do
            [ -e "$dev" ] || continue
            if ${pkgs.hdparm}/bin/hdparm -C "$dev" 2>/dev/null | grep -q "active/idle"; then
              disks_spinning=true
              break
            fi
          done
          shopt -u nullglob

          # Hysterese-Entscheidung
          if [ "$CACHE_USAGE" -ge "${toString cfgMover.capacityThreshold}" ]; then
            echo "SSD-Auslastung kritisch ($CACHE_USAGE%). Erzwinge Migration..."
          elif [ "$disks_spinning" = true ]; then
            echo "HDDs drehen bereits ($CACHE_USAGE% SSD). Opportunistische Migration..."
          else
            echo "HDDs im Standby, SSD-Auslastung ($CACHE_USAGE%) unter Schwellwert (${toString cfgMover.capacityThreshold}%). Abbruch."
            exit 0
          fi

          echo "Starte Migration ${cfgMover.sourceDir} → ${cfgMover.targetDir}..."
          ${pkgs.rclone}/bin/rclone move "${cfgMover.sourceDir}" "${cfgMover.targetDir}" \
            --min-age "${cfgMover.minAge}" \
            --delete-empty-src-dirs \
            --transfers=${toString cfgMover.rcloneTransfers} \
            --checkers=${toString cfgMover.rcloneCheckers} \
            ${excludeFlags} \
            -v \
            --log-file=/var/log/nixhome-storage-mover/rclone.log

          # Setgid auf neu angelegten Verzeichnissen erzwingen
          find "${cfgMover.targetDir}" -type d ! -perm -g+s -exec chmod g+s {} + 2>/dev/null || true
        '';

        # Härtung & Sandboxing
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_FOWNER"
          "CAP_DAC_OVERRIDE"
          "CAP_SYS_RAWIO" # hdparm -C benötigt HDIO_DRIVE_CMD ioctl
        ];
        ReadWritePaths = [
          cfgMover.sourceDir
          cfgMover.targetDir
          "/var/log/nixhome-storage-mover"
        ];
        LogsDirectory = "nixhome-storage-mover";

        # Hintergrund-Job: Idle I/O + CPU → kein Impact auf interaktive Nutzung
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
        Nice = 19;
      };
    };

    # OnCalendar bleibt: Tier-Migration ist Betriebsfenster, nicht reaktiv pro Schreibvorgang.
    systemd.timers.nixhome-storage-mover = {
      description = "Precision Storage Cache Mover (Nacht-Fenster)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfgMover.onCalendar;
        Persistent = true;
      };
    };
  };
}
