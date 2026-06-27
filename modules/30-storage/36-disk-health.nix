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
}: let
  cfg = config.my.disk-health;
  scrutinyPort = config.my.ports.scrutiny;
in {
  options.my.disk-health = {
    enable = lib.mkEnableOption "SMART monitoring via smartd and Scrutiny WebUI";
    spinDownMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "HDD spindown via smartd -n standby (Minuten).";
    };
  };

  config = lib.mkIf cfg.enable {
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
  };
}
