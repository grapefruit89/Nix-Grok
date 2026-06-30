# ---
# meta:
#   layer: 3
#   role: module
#   purpose: smartd + Scrutiny für Tier-C HDDs (SMART-Monitoring)
#   docs:
#     - docs/guides/GUIDE-disk-health.md
#   tags:
#     - storage
#     - smartd
#     - scrutiny
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.disk-health;
  scrutinyPort = config.my.ports.scrutiny;
in
{
  options.my.disk-health = {
    enable = lib.mkEnableOption "SMART monitoring via smartd and Scrutiny WebUI";
    spinDownMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "HDD spindown via smartd -n standby (Minuten).";
    };
    hdIdle = {
      enable = lib.mkEnableOption "hd-idle daemon: spinnt Rotationsplatten nach Inaktivität";
      secondsToSpinDown = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Sekunden bis zum Spindown (Standard: 300s = 5 min).";
      };
    };
  };

  config = lib.mkMerge [
    # ── SMART + SCRUTINY ─────────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      my.storage-policy.tierCExemptions = lib.mkAfter [
        "smartd"
        "scrutiny"
        "influxdb2"
      ];

      my.impermanence.extraPaths = [
        "/var/lib/scrutiny"
        "/var/lib/influxdb2"
      ];

      services.scrutiny = {
        enable = true;
        influxdb.enable = true;
        collector.enable = true;
        settings = {
          web.listen = {
            port = scrutinyPort;
            host = "127.0.0.1";
          };
          # Explizit 127.0.0.1 — global disable_ipv6 bricht [::1]:8086
          web.influxdb.host = "127.0.0.1";
          log.level = "INFO";
        };
      };

      services.smartd = {
        enable = true;
        autodetect = true;
        notifications.test = false;
        notifications.mail.enable = false;
        devices = [
          {
            device = "DEVICESCAN";
            options = "-a -o on -S on -n standby,${toString cfg.spinDownMinutes},q";
          }
        ];
      };

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "check-smartd-active" ''
          set -euo pipefail
          if ${pkgs.systemd}/bin/systemctl is-active --quiet smartd.service; then
            echo "OK: smartd.service aktiv"
            exit 0
          fi
          echo "ERROR: smartd.service nicht aktiv"
          exit 1
        '')
        (pkgs.writeShellScriptBin "check-scrutiny-health" ''
          set -euo pipefail
          if ${pkgs.curl}/bin/curl -fsS -m 10 "http://127.0.0.1:${toString scrutinyPort}/health" >/dev/null; then
            echo "OK: Scrutiny health endpoint"
            exit 0
          fi
          echo "ERROR: Scrutiny nicht erreichbar auf Port ${toString scrutinyPort}"
          exit 1
        '')
        (pkgs.writeShellScriptBin "check-hdd-smart" ''
          set -euo pipefail
          SMARTCTL="${pkgs.smartmontools}/bin/smartctl"
          LSBLK="${pkgs.util-linux}/bin/lsblk"
          failures=0
          checked=0
          while read -r name rota; do
            [ "$rota" = "1" ] || continue
            dev="/dev/$name"
            [ -b "$dev" ] || continue
            checked=$((checked + 1))
            if ! $SMARTCTL -H "$dev" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qi "PASSED"; then
              echo "FAIL: SMART health check failed for $dev"
              failures=$((failures + 1))
            fi
          done < <($LSBLK -d -o NAME,ROTA -n)
          if [ "$checked" -eq 0 ]; then
            echo "OK: keine HDDs angeschlossen (Tier C optional)"
            exit 0
          fi
          if [ "$failures" -ne 0 ]; then
            exit 1
          fi
          echo "OK: $checked HDD(s) SMART PASSED"
          exit 0
        '')
      ];
    })

    # ── HD-IDLE: Rotationsplatten nach Inaktivität spinnen ───────────────────
    # Hinweis: Auf q958 (tierC.enabled = false, keine HDDs) ist dieser Service
    # inert — er findet keine rotating disks und läuft mit "-i 0" (kein Spindown).
    # Aktiv wird er sobald Tier-C HDDs angeschlossen werden.
    (lib.mkIf cfg.hdIdle.enable {
      systemd.services.hd-idle = {
        description = "HDD Spindown nach ${toString cfg.hdIdle.secondsToSpinDown}s Inaktivität";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart =
            let
              script = pkgs.writeShellScript "hd-idle-start" ''
                set -euo pipefail
                # -i 0: Globaler Default = kein Spindown. Pro HDD überschreiben.
                args="-i 0"
                while read -r name rota; do
                  [ "$rota" = "1" ] || continue
                  args="$args -a /dev/$name -i ${toString cfg.hdIdle.secondsToSpinDown}"
                done < <(${pkgs.util-linux}/bin/lsblk -d -o NAME,ROTA -n 2>/dev/null)
                exec ${pkgs.hd-idle}/bin/hd-idle $args
              '';
            in
            "${script}";
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };
    })
  ];
}
