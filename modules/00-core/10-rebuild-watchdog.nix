# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Rebuild-Notstop — Zeit+CPU-Druck (PSI), Sentinel, Rollback
#   tags:
#     - rebuild
#     - watchdog
#     - safety
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.core.rebuild-watchdog;
  guard = import ../../lib/rebuild-guard.nix { inherit lib; };
  systemctl = "${pkgs.systemd}/bin/systemctl";
  switchToConf = "/nix/var/nix/profiles/system/bin/switch-to-configuration";
  realRebuild = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
  stormList = lib.concatStringsSep " " cfg.stormPathUnits;
  sustainTimer = "nixos-rebuild-load-sustain.timer";
  psiFile = "/proc/pressure/cpu";
  psiThreshold =
    if cfg.loadThresholdRatio != null then cfg.loadThresholdRatio * 100 else cfg.psiSomeAvg10Threshold;

  readPsiSomeAvg10 = "${pkgs.gawk}/bin/gawk 'match($0,/some avg10=([0-9.]+)/,a){print a[1];exit}' ${psiFile}";
  readPsiSomeAvg60 = "${pkgs.gawk}/bin/gawk 'match($0,/avg60=([0-9.]+)/,a){print a[1];exit}' ${psiFile}";

  notstopScript = pkgs.writeShellScript "nixos-rebuild-notstop" (
    builtins.concatStringsSep "\n" [
      "set -euo pipefail"
      "SESSION=/run/nixos-rebuild-watchdog/session"
      "SENTINEL=${guard.sentinel}"
      "REASON_FILE=/run/nixos-rebuild-watchdog/notstop-reason"
      "LOG=/var/log/nixos-rebuild-watchdog/notstop.log"
      "PREV=/nix/var/nix/profiles/system-1-link"
      "STORM=\"${stormList}\""
      "REASON=timeout"
      "[ -f \"$REASON_FILE\" ] && REASON=$(${pkgs.coreutils}/bin/cat \"$REASON_FILE\")"
      "${pkgs.coreutils}/bin/mkdir -p /var/log/nixos-rebuild-watchdog"
      "log() { echo \"$(date -Is) [$REASON] $*\" | ${pkgs.coreutils}/bin/tee -a \"$LOG\"; }"
      "SWITCH_ACTIVE=no"
      "STATE=$(${systemctl} is-active nixos-rebuild-switch-to-configuration.service 2>/dev/null || true)"
      "[ \"$STATE\" = active ] && SWITCH_ACTIVE=yes"
      "${pkgs.coreutils}/bin/pgrep -f nixos-rebuild >/dev/null 2>&1 && SWITCH_ACTIVE=yes || true"
      "HAS_SESSION=no"
      "[ -f \"$SESSION\" ] && HAS_SESSION=yes"
      "if [ \"$HAS_SESSION\" != yes ] && [ \"$SWITCH_ACTIVE\" != yes ] && [ \"$REASON\" != load ]; then log skip; exit 0; fi"
      "stop_storm() { for u in $STORM; do ${systemctl} stop \"$u\" 2>/dev/null || true; done; }"
      "if [ \"$HAS_SESSION\" != yes ] && [ \"$SWITCH_ACTIVE\" != yes ] && [ \"$REASON\" = load ]; then"
      "  log \"CPU-Notbremse — Sturm-Path-Units\""
      "  rm -f \"$SENTINEL\" \"$REASON_FILE\" /run/nixos-rebuild-watchdog/high-load-since"
      "  ${systemctl} stop ${sustainTimer} 2>/dev/null || true"
      "  stop_storm"
      "  ${systemctl} reset-failed 2>/dev/null || true"
      "  exit 0"
      "fi"
      "log \"NOTSTOP — Abbruch + Rollback\""
      "rm -f \"$SENTINEL\" \"$REASON_FILE\" /run/nixos-rebuild-watchdog/high-load-since"
      "${systemctl} stop nixos-rebuild-watchdog.timer 2>/dev/null || true"
      "${systemctl} stop ${sustainTimer} 2>/dev/null || true"
      "${systemctl} stop nixos-rebuild-switch-to-configuration.service 2>/dev/null || true"
      "${pkgs.coreutils}/bin/pkill -TERM -f nixos-rebuild 2>/dev/null || true"
      "sleep 2"
      "${pkgs.coreutils}/bin/pkill -KILL -f nixos-rebuild 2>/dev/null || true"
      "stop_storm"
      "if [ -L \"$PREV\" ]; then log \"Rollback $PREV\"; ${switchToConf} switch \"$PREV\" || log rollback-fail; fi"
      "${systemctl} reset-failed 2>/dev/null || true"
      "rm -f \"$SESSION\""
      "log fertig"
    ]
  );

  loadWatchScript = pkgs.writeShellScript "nixos-rebuild-load-watch" ''
    set -euo pipefail
    PSI=$(${readPsiSomeAvg10}); PSI=''${PSI:-0}
    THRESH=${toString psiThreshold}
    STATE=/run/nixos-rebuild-watchdog/high-load-since
    LOG=/var/log/nixos-rebuild-watchdog/load-guard.log
    SUSTAIN_TIMER=${sustainTimer}
    ${pkgs.coreutils}/bin/mkdir -p /var/log/nixos-rebuild-watchdog
    if ${pkgs.gawk}/bin/gawk -v p="$PSI" -v t="$THRESH" 'BEGIN{exit !(p+0>=t+0)}'; then
      NOW=$(${pkgs.coreutils}/bin/date +%s)
      if [ ! -f "$STATE" ]; then
        echo "$NOW" > "$STATE"
        echo "$(date -Is) psi_some_avg10=$PSI >= $THRESH — Beobachtung ${toString cfg.loadSustainSec}s (PSI-event)" >> "$LOG"
      fi
      if ! ${systemctl} is-active --quiet "$SUSTAIN_TIMER" 2>/dev/null; then
        ${systemctl} start "$SUSTAIN_TIMER"
      fi
    else
      if [ -f "$STATE" ]; then
        echo "$(date -Is) psi_some_avg10=$PSI < $THRESH — Beobachtung abgebrochen" >> "$LOG"
      fi
      rm -f "$STATE"
      ${systemctl} stop "$SUSTAIN_TIMER" 2>/dev/null || true
    fi
  '';

  loadSustainScript = pkgs.writeShellScript "nixos-rebuild-load-sustain" ''
    set -euo pipefail
    PSI=$(${readPsiSomeAvg10}); PSI=''${PSI:-0}
    THRESH=${toString psiThreshold}
    STATE=/run/nixos-rebuild-watchdog/high-load-since
    LOG=/var/log/nixos-rebuild-watchdog/load-guard.log
    SUSTAIN=${toString cfg.loadSustainSec}
    SUSTAIN_TIMER=${sustainTimer}
    ${pkgs.coreutils}/bin/mkdir -p /var/log/nixos-rebuild-watchdog
    if ! ${pkgs.gawk}/bin/gawk -v p="$PSI" -v t="$THRESH" 'BEGIN{exit !(p+0>=t+0)}'; then
      echo "$(date -Is) psi_some_avg10=$PSI < $THRESH — Sustain-Timer stoppen" >> "$LOG"
      rm -f "$STATE"
      ${systemctl} stop "$SUSTAIN_TIMER" 2>/dev/null || true
      exit 0
    fi
    if [ ! -f "$STATE" ]; then
      echo "$(${pkgs.coreutils}/bin/date +%s)" > "$STATE"
    fi
    NOW=$(${pkgs.coreutils}/bin/date +%s)
    SINCE=$(${pkgs.coreutils}/bin/cat "$STATE")
    ELAPSED=$((NOW - SINCE))
    if [ "$ELAPSED" -ge "$SUSTAIN" ]; then
      echo "$(date -Is) psi_some_avg10=$PSI sustained ${toString cfg.loadSustainSec}s — NOTSTOP" >> "$LOG"
      echo load > /run/nixos-rebuild-watchdog/notstop-reason
      ${systemctl} stop "$SUSTAIN_TIMER" 2>/dev/null || true
      ${systemctl} start nixos-rebuild-watchdog.service
    fi
  '';

  psiSamplerScript = pkgs.writeShellScript "nixos-rebuild-psi-sampler" ''
    set -euo pipefail
    LOG=/var/log/nixos-rebuild-watchdog/psi-calibration.csv
    MAX=5242880
    PSI10=$(${readPsiSomeAvg10}); PSI10=''${PSI10:-0}
    PSI60=$(${readPsiSomeAvg60}); PSI60=''${PSI60:-0}
    LOAD1=$(${pkgs.gawk}/bin/gawk '{print $1}' /proc/loadavg)
    THRESH=${toString psiThreshold}
    SUSTAIN=$(${systemctl} is-active ${sustainTimer} 2>/dev/null || echo inactive)
    SENTINEL=no
    [ -f ${guard.sentinel} ] && SENTINEL=yes
    ${pkgs.coreutils}/bin/mkdir -p /var/log/nixos-rebuild-watchdog
    if [ ! -f "$LOG" ]; then
      echo "timestamp,psi_some_avg10,psi_some_avg60,load1,threshold,sustain_active,sentinel" > "$LOG"
    fi
    echo "$(date -Is),$PSI10,$PSI60,$LOAD1,$THRESH,$SUSTAIN,$SENTINEL" >> "$LOG"
    SZ=$(${pkgs.coreutils}/bin/stat -c%s "$LOG" 2>/dev/null || echo 0)
    if [ "$SZ" -gt "$MAX" ]; then
      ${pkgs.coreutils}/bin/tail -n 4000 "$LOG" > "$LOG.tmp"
      ${pkgs.coreutils}/bin/mv "$LOG.tmp" "$LOG"
    fi
  '';
in
{
  options.my.core.rebuild-watchdog = {
    enable = lib.mkEnableOption ''
      Rebuild-Schutz für switch/test (dry-build ohne Zeit-Watchdog): Zeit-Notstop, CPU-Druck (PSI), Sentinel, Rollback.
    '';
    timeoutSec = lib.mkOption {
      type = lib.types.int;
      default = 480;
      description = "Max. Sekunden nur switch/test-Phase (dry-build ohne Watchdog). Default 8min, max 600.";
    };
    dryBuildTargetSec = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "dry-build-Ziel in Sekunden (Hinweis wenn überschritten, kein Abbruch).";
    };
    dryBuildMaxSec = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "Warn-Schwelle — stderr-Warnung + Log ab diesem Wert (Ziel: dryBuildTargetSec).";
    };
    dryBuildFailOnExceed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "dry-build bei Überschreitung von dryBuildMaxSec abbrechen (sonst nur Warnung).";
    };
    loadSustainSec = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Anhaltende CPU-Überlastung (Sek.) bis Notbremse. Default 5min, max 8min.";
    };
    psiSomeAvg10Threshold = lib.mkOption {
      type = lib.types.float;
      default = 50.0;
      description = ''
        PSI CPU `some avg10` Schwelle (0–100). Kalibrierung via psi-calibration.csv.
      '';
    };
    psiCalibrationSampleSec = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "PSI-Langzeit-Sampling-Intervall (Sek.) für Schwellen-Kalibrierung.";
    };
    loadThresholdRatio = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      description = "Veraltet — nutze psiSomeAvg10Threshold. Wenn gesetzt: psi = Ratio × 100.";
    };
    loadPollSec = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Prüfintervall während der Beobachtungsphase (Sustain-Timer), nicht im Idle.";
    };
    stormPathUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = guard.stormPathUnits;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.timeoutSec > 0 && cfg.timeoutSec <= 600;
        message = "rebuild-watchdog.timeoutSec: 1–600.";
      }
      {
        assertion = cfg.loadSustainSec >= 180 && cfg.loadSustainSec <= 480;
        message = "rebuild-watchdog.loadSustainSec: 180–480.";
      }
      {
        assertion = psiThreshold >= 10 && psiThreshold <= 95;
        message = "rebuild-watchdog.psiSomeAvg10Threshold: 10–95.";
      }
    ];

    environment.variables.NIXOS_REBUILD_BIN = realRebuild;

    environment.etc."nixos-rebuild/config.env".text = lib.concatStringsSep "\n" [
      "DRY_BUILD_TARGET=${toString cfg.dryBuildTargetSec}"
      "DRY_BUILD_MAX=${toString cfg.dryBuildMaxSec}"
      "DRY_BUILD_STRICT=${if cfg.dryBuildFailOnExceed then "1" else "0"}"
      "SWITCH_TIMEOUT=${toString cfg.timeoutSec}"
      ""
    ];

    systemd.tmpfiles.rules = [
      "d /run/nixos 0755 root root -"
      "d /run/nixos-rebuild-watchdog 0755 root root -"
      "d /var/log/nixos-rebuild-watchdog 0755 root root -"
      "d /var/log/nixos-rebuild 0755 root root -"
    ];

    systemd.services.nixos-rebuild-watchdog = {
      description = "Notstop — Zeit/CPU: Rebuild abbrechen + Rollback";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = notstopScript;
      };
    };

    systemd.timers.nixos-rebuild-watchdog = {
      description = "Zeit-Notstop (nur switch/test — dry-build ohne Timer)";
      timerConfig = {
        OnActiveSec = "${toString cfg.timeoutSec}s";
        AccuracySec = "10s";
      };
    };

    systemd.paths.nixos-rebuild-load-watch = {
      description = "CPU-Druck-Schwelle — PSI-Event auf /proc/pressure/cpu";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = psiFile;
      };
    };

    systemd.services.nixos-rebuild-load-watch = {
      description = "CPU-Druck (PSI) prüfen — event-gesteuert";
      path = with pkgs; [
        gawk
        coreutils
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = loadWatchScript;
      };
    };

    systemd.services.nixos-rebuild-load-sustain = {
      description = "CPU-Druck-Beobachtung (nur bei Überschreitung)";
      path = with pkgs; [
        gawk
        coreutils
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = loadSustainScript;
      };
    };

    systemd.timers.nixos-rebuild-load-sustain = {
      description = "CPU-Druck-Beobachtung — läuft nur nach Schwellen-Überschreitung";
      timerConfig = {
        OnActiveSec = "1s";
        OnUnitActiveSec = "${toString cfg.loadPollSec}s";
        AccuracySec = "15s";
      };
    };

    systemd.services.nixos-rebuild-psi-sampler = {
      description = "PSI-Langzeit-Sampling für Schwellen-Kalibrierung";
      path = with pkgs; [
        gawk
        coreutils
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = psiSamplerScript;
      };
    };

    systemd.timers.nixos-rebuild-psi-sampler = {
      description = "PSI alle ${toString cfg.psiCalibrationSampleSec}s sampeln";
      wantedBy = [ "multi-user.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "${toString cfg.psiCalibrationSampleSec}s";
        AccuracySec = "1min";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nixos-rebuild" ''
        if [[ "''${1:-}" == "switch" || "''${1:-}" == "test" ]]; then
          exec /etc/nixos/scripts/nixos-rebuild-safe.sh "''${1}"
        fi
        exec ${realRebuild} "$@"
      '')
    ];
  };
}
