{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.abandonware-monitor;

  # Simple bash script to check GitHub repos
  checkScript = pkgs.writeShellScript "abandonware-check" ''
    set -euo pipefail

    MODULES_PATH="$1"
    THRESHOLD_DAYS=365
    CURRENT_TIME=$(date +%s)

    # 1. Parse all upstream_repo tags from NIXMETA headers in modules directory
    if [ ! -d "$MODULES_PATH" ]; then
      echo "Error: Modules path $MODULES_PATH does not exist."
      exit 1
    fi

    # Find all unique upstream_repo values
    REPOS=$(${pkgs.gnugrep}/bin/grep -roE 'upstream_repo:\s*"[^"]+"' "$MODULES_PATH" | cut -d'"' -f2 | sort -u || true)

    if [ -z "$REPOS" ]; then
      echo "No upstream_repo entries found in NIXMETA headers."
      exit 0
    fi

    for REPO in $REPOS; do
      echo "Checking $REPO..."
      API_URL="https://api.github.com/repos/$REPO"
      
      RESPONSE=$(${pkgs.curl}/bin/curl -sS --fail "$API_URL" || true)
      
      if [ -z "$RESPONSE" ]; then
        echo "Failed to fetch data for $REPO. Skipping."
        continue
      fi

      PUSHED_AT=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.pushed_at // .updated_at')
      
      if [ "$PUSHED_AT" == "null" ] || [ -z "$PUSHED_AT" ]; then
        echo "Could not parse date for $REPO."
        continue
      fi

      PUSHED_TS=$(date -d "$PUSHED_AT" +%s)
      DIFF_DAYS=$(( (CURRENT_TIME - PUSHED_TS) / 86400 ))

      if [ "$DIFF_DAYS" -gt "$THRESHOLD_DAYS" ]; then
        echo "ALERT: Abandonware detected! Repository $REPO has not been updated in $DIFF_DAYS days (Last update: $PUSHED_AT)." | ${pkgs.systemd}/bin/systemd-cat -p crit -t abandonware-monitor
      else
        echo "OK: $REPO is active (last update $DIFF_DAYS days ago)."
      fi
      
      sleep 2
    done
  '';

in
{
  options.my.services.abandonware-monitor = {
    enable = lib.mkEnableOption "Abandonware Monitor";
    modulesPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/modules";
      description = "Path to the Nix modules directory to parse NIXMETA headers from.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.abandonware-monitor = {
      description = "Checks GitHub repositories for inactivity (>365 days)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkScript} ${cfg.modulesPath}";

        # Hardening
        User = "nobody";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    systemd.timers.abandonware-monitor = {
      description = "Weekly Abandonware Check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15min";
        OnUnitActiveSec = "7d";
        RandomizedDelaySec = "1h";
      };
    };
  };
}
