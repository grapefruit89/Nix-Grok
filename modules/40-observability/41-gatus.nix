# ---
# meta:
#   id: NIXH-41-MOD-001
#   layer: 3
#   role: module
#   purpose: Gatus Status-Dashboard — Health-Checks, SSH-Wrapper, Pool/Service-Check-Scripts
#   lib:
#     - lib/gatus-endpoints.nix
#     - lib/unix-sockets.nix
#     - lib/systemd-hardening.nix
#   services:
#     - gatus
#   tags:
#     - observability
#     - gatus
#     - monitoring
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.gatus;
  sockets = import ../../lib/unix-sockets.nix { inherit lib; };
  hardening = import ../../lib/systemd-hardening.nix { inherit lib; };
  yaml = pkgs.formats.yaml { };
  gatusLib = import ../../lib/gatus-endpoints.nix { inherit lib config; };

  # Factory: MergerFS-Pool-Healthcheck — ersetzt drei identische Scripts
  mkPoolCheck =
    {
      name,
      poolMount,
      branchDir,
    }:
    pkgs.writeShellScriptBin "check-${name}" ''
      set -euo pipefail
      MOUNTPOINT="${pkgs.util-linux}/bin/mountpoint"
      if ! "$MOUNTPOINT" -q "${poolMount}"; then
        echo "ERROR: MergerFS pool '${poolMount}' is not mounted!"
        exit 2
      fi
      shopt -s nullglob
      mounted_branches=0
      for dir in "${branchDir}"/*; do
        if [ -d "$dir" ] && "$MOUNTPOINT" -q "$dir"; then
          mounted_branches=$((mounted_branches + 1))
        fi
      done
      if [ "$mounted_branches" -eq 0 ]; then
        echo "ERROR: No branches are mounted under ${branchDir}!"
        exit 1
      fi
      echo "OK: Pool '${poolMount}' is healthy with $mounted_branches active branches."
      exit 0
    '';
in
{
  options.my.services.gatus = {
    enable = lib.mkEnableOption "Gatus status and health monitoring dashboard";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.gatus;
      description = "Port for the Gatus dashboard.";
    };
    endpointsFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/gatus/endpoints.yaml";
      description = "Path to the Gatus YAML config file containing endpoints (loaded at runtime).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."gatus/endpoints.yaml".source =
      (yaml.generate "gatus-endpoints.yaml" gatusLib).outPath;

    users.users.monitoring = {
      isSystemUser = true;
      group = "media";
      extraGroups = lib.mkIf (config.my.services.valkey.enable or false) [ "redis-valkey" ];
      home = "/var/lib/monitoring";
      createHome = true;
      shell = pkgs.bash;
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "gatus-ssh-wrapper" ''
        set -euo pipefail
        case "$SSH_ORIGINAL_COMMAND" in
          /run/current-system/sw/bin/check-*)
            exec $SSH_ORIGINAL_COMMAND
            ;;
          *)
            echo "Access denied. Only registered health check binaries are allowed."
            exit 1
            ;;
        esac
      '')

      (mkPoolCheck {
        name = "fast-pool";
        poolMount = "/mnt/fast_pool";
        branchDir = "/mnt/tier-b";
      })
      (mkPoolCheck {
        name = "media-pool";
        poolMount = "/mnt/media";
        branchDir = "/mnt/tier-c";
      })
      (mkPoolCheck {
        name = "external-pool";
        poolMount = "/mnt/external_pool";
        branchDir = "/mnt/external";
      })

      (pkgs.writeShellScriptBin "check-permissions-drift" ''
        set -euo pipefail
        drift_detected=0
        shopt -s nullglob
        for dir in "/mnt/tier-b"/* "/mnt/tier-c"/*; do
          [ -d "$dir" ] || continue
          owner=$(stat -c "%u:%g" "$dir")
          perms=$(stat -c "%a" "$dir")
          if [ "$owner" != "0:${toString config.my.groups.registry.media}" ]; then
            echo "DRIFT: Directory $dir is owned by $owner, expected 0:${toString config.my.groups.registry.media}"
            drift_detected=1
          fi
          if [ "$perms" != "775" ] && [ "$perms" != "2775" ]; then
            echo "DRIFT: Directory $dir has permissions $perms, expected 775/2775"
            drift_detected=1
          fi
        done
        if [ "$drift_detected" -ne 0 ]; then
          exit 1
        fi
        echo "OK: Permissions and ownership on all Tier B/C mountpoints are healthy."
        exit 0
      '')

      (pkgs.writeShellScriptBin "check-postgres-uds" ''
        set -euo pipefail
        if ${pkgs.postgresql}/bin/pg_isready -h /run/postgresql -p 5432; then
          echo "OK: PostgreSQL socket is responding"
          exit 0
        else
          echo "ERROR: PostgreSQL socket not responding"
          exit 1
        fi
      '')

      (pkgs.writeShellScriptBin "check-valkey-uds" ''
        set -euo pipefail
        if [ -S "${sockets.valkey}" ]; then
          response=$(${pkgs.valkey}/bin/valkey-cli -s ${sockets.valkey} ping)
          if [ "$response" = "PONG" ]; then
            echo "OK: Valkey socket is responding with PONG"
            exit 0
          fi
        fi
        echo "ERROR: Valkey socket not responding"
        exit 1
      '')

      (pkgs.writeShellScriptBin "check-grafana-uds" ''
        set -euo pipefail
        if ${pkgs.curl}/bin/curl -fsS --unix-socket ${sockets.grafana} http://localhost/api/health | ${pkgs.jq}/bin/jq -e '.database == "ok"' >/dev/null; then
          echo "OK: Grafana socket is healthy"
          exit 0
        else
          echo "ERROR: Grafana socket health check failed"
          exit 1
        fi
      '')

      (pkgs.writeShellScriptBin "check-restic-backup" ''
        set -euo pipefail
        status=$(systemctl show --property=ExecMainStatus,ActiveEnterTimestamp restic-backups-tier-a-sovereign.service)
        exit_code=$(echo "$status" | grep "ExecMainStatus" | cut -d= -f2)
        last_run_time=$(echo "$status" | grep "ActiveEnterTimestamp" | cut -d= -f2)
        if [ "$exit_code" != "0" ]; then
          echo "ERROR: Last backup failed with exit code $exit_code!"
          exit 1
        fi
        if [ -z "$last_run_time" ]; then
          echo "ERROR: Backup has never run!"
          exit 2
        fi
        last_unix=$(date -d "$last_run_time" +%s)
        current_unix=$(date +%s)
        diff_hours=$(( (current_unix - last_unix) / 3600 ))
        if [ "$diff_hours" -ge 28 ]; then
          echo "ERROR: Last backup was $diff_hours hours ago (expected < 28h)!"
          exit 3
        fi
        echo "OK: Last backup was successful ($diff_hours hours ago)."
        exit 0
      '')
    ];

    services = {
      openssh.extraConfig = ''
        Match User monitoring
          ForceCommand /run/current-system/sw/bin/gatus-ssh-wrapper
          AllowTcpForwarding no
          X11Forwarding no
          AllowAgentForwarding no
      '';
      gatus = {
        enable = true;
        settings = {
          web.address = "127.0.0.1";
          web.port = cfg.port;
        };
      };
    };

    systemd.services.gatus = {
      after = [ "network.target" ];
      preStart = lib.mkAfter ''
        if [ -f /var/lib/secrets/gatus_ssh_key ]; then
          install -D -m 600 -o gatus -g gatus /var/lib/secrets/gatus_ssh_key /var/lib/gatus/ssh_key
        fi
      '';
      environment.GATUS_CONFIG_PATH = lib.mkForce cfg.endpointsFile;
      serviceConfig = lib.mkMerge [
        (hardening.mkHardened { })
        { StateDirectory = "gatus"; }
      ];
    };
  };
}
