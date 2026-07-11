# ---
# meta:
#   id: NIXH-05-MOD-006
#   layer: 3
#   role: module
#   purpose: Post-Boot Fail-Fast — kritische Dienste nach Grace-Period prüfen (read-only)
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
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.systemd
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = pkgs.writeShellScript "boot-watchdog-wait" ''
          set -euo pipefail
          DEADLINE=$(($(date +%s) + ${toString cfg.graceSec}))
          while [ $(date +%s) -lt "$DEADLINE" ]; do
            READY=true
            ${lib.optionalString cfg.requireBlocky "systemctl is-active --quiet blocky.service || READY=false"}
            ${lib.optionalString cfg.requirePostgresql "systemctl is-active --quiet postgresql.service || READY=false"}
            ${lib.optionalString cfg.requireCaddy "systemctl is-active --quiet caddy.service || READY=false"}
            if [ "$READY" = true ]; then
              exit 0
            fi
            sleep 5
          done
        '';
        ExecStart = pkgs.writeShellScript "boot-watchdog" ''
          set -euo pipefail
          ${lib.optionalString cfg.requireBlocky (serviceActive "blocky.service")}
          ${lib.optionalString cfg.requirePostgresql (serviceActive "postgresql.service")}
          ${lib.optionalString cfg.requireCaddy (serviceActive "caddy.service")}
          echo "[BOOT-WATCHDOG] OK: kritische Dienste aktiv"
        '';
      };
    };

  };
}
