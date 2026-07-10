# ---
# meta:
#   id: NIXH-05-MOD-006
#   layer: 3
#   role: module
#   purpose: Post-Boot Fail-Fast — kritische Dienste nach Grace-Period prüfen
#   docs:
#     - docs/adr/005-critical-systemd-restart.md
#   tags:
#     - boot
#     - watchdog
#     - systemd
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.boot-watchdog;
  # Reiner Health-Check — kein manueller Restart, kein sleep.
  # Restart-Policies gehören in das jeweilige Service-Modul (wie postgresql unten).
  serviceActive = name: ''
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet ${name}; then
      echo "[BOOT-WATCHDOG] FEHLER: ${name} nicht aktiv"
      exit 1
    fi
  '';
in
{
  options.my.boot-watchdog = {
    enable = lib.mkEnableOption "Post-boot health check for critical infrastructure services";
    graceSec = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = "Sekunden nach Boot bevor die Prüfung startet.";
    };
    requirePostgresql = lib.mkOption {
      type = lib.types.bool;
      default = config.my.services.postgresql.enable or false;
    };
    requireCaddy = lib.mkOption {
      type = lib.types.bool;
      default = config.services.caddy.enable or false;
    };
    requireBlocky = lib.mkOption {
      type = lib.types.bool;
      default = config.my.services.blocky.enable or false;
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.boot-watchdog = {
      description = "Post-boot critical service health check (fail-fast)";
      after = [
        "multi-user.target"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        ${lib.optionalString cfg.requireBlocky (serviceActive "blocky.service")}
        ${lib.optionalString cfg.requirePostgresql (serviceActive "postgresql.service")}
        ${lib.optionalString cfg.requireCaddy (serviceActive "caddy.service")}
        echo "[BOOT-WATCHDOG] OK: kritische Dienste aktiv"
      '';
      path = [ pkgs.systemd ];
    };

    systemd.timers.boot-watchdog = {
      description = "Run boot-watchdog once after boot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "${toString cfg.graceSec}s";
        AccuracySec = "30s";
      };
    };

    # PostgreSQL: Restart=always ohne OOM-Konflikt mit memory.postgres (-800)
    systemd.services.postgresql = lib.mkIf (config.services.postgresql.enable or false) {
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = lib.mkForce "5s";
        StartLimitIntervalSec = lib.mkForce 0;
        StartLimitBurst = lib.mkForce 0;
        TimeoutStopSec = lib.mkForce "30s";
      };
    };

    # Caddy: Restart-Policy (wenn watchdog überwacht)
    systemd.services.caddy = lib.mkMerge [
      (lib.mkIf cfg.requireCaddy {
        serviceConfig = {
          Restart = lib.mkDefault "on-failure";
          RestartSec = lib.mkDefault "5s";
          StartLimitIntervalSec = lib.mkDefault 0;
          StartLimitBurst = lib.mkDefault 0;
        };
      })
    ];

    # Blocky: Restart-Policy — watchdog prüft, systemd erholt sich selbst
    systemd.services.blocky = lib.mkIf cfg.requireBlocky {
      serviceConfig = {
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault "5s";
        StartLimitIntervalSec = lib.mkDefault 0;
        StartLimitBurst = lib.mkDefault 0;
      };
    };
  };
}
