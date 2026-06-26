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
  yaml = pkgs.formats.yaml { };

  scrutinyConfig = {
    version = 1;
    web = {
      listen = {
        port = scrutinyPort;
        host = "127.0.0.1";
        basepath = "";
      };
      database.location = "/var/lib/scrutiny/scrutiny.db";
      # Explizit 127.0.0.1 — global disable_ipv6 bricht [::1]:8086
      influxdb = {
        host = "127.0.0.1";
        port = 8089;
      };
    };
    log = {
      file = "";
      level = "INFO";
    };
  };

in
{
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
    ];

    my.impermanence.extraPaths = [ "/var/lib/scrutiny" ];

    systemd.tmpfiles.rules = [
      "d /var/lib/scrutiny 0750 root root -"
      "d /etc/scrutiny 0755 root root -"
    ];

    environment.etc."scrutiny/scrutiny.yaml".source =
      (yaml.generate "scrutiny.yaml" scrutinyConfig).outPath;

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

    systemd.services.scrutiny = {
      description = "Scrutiny SMART disk health dashboard";
      after = [
        "smartd.service"
        "network.target"
      ];
      wants = [ "smartd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        ExecStart = "${pkgs.scrutiny}/bin/scrutiny start --config /etc/scrutiny/scrutiny.yaml";
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "scrutiny";
        ReadWritePaths = [ "/var/lib/scrutiny" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
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
