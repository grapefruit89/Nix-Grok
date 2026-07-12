# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Langzeit-Host-Health — PSI/Swap/RSS-Sampler + Grafana-Dashboard
#   docs:
#     - docs/memory_oom.md
#   services:
#     - victoriametrics
#     - grafana
#     - prometheus-node-exporter
#   tags:
#     - observability
#     - memory
#     - host-health
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.observability.hostHealth;
  cfgVM = config.my.observability.victoriametrics;
  cpuCores = 4; # q958 i3-9100 — später aus profile.nix ableitbar

  textfileDir = "/var/lib/node-exporter-textfile";
  csvLog = "/var/log/host-health/metrics.csv";
  csvMaxBytes = 5242880;

  trackedServices = [
    "loki"
    "sonarr"
    "radarr"
    "prowlarr"
    "lidarr"
    "readarr"
    "jellyfin"
    "paperless-web"
    "home-assistant"
    "seerr"
    "open-webui-backend"
    "grafana"
    "vector"
    "zigbee2mqtt"
  ];

  trackedUsers = [
    "moritz"
    "amp"
  ];

  readPsiAvg10 = type: resource: ''
    ${pkgs.gawk}/bin/gawk -v t="${type}" -v r="${resource}" '
      $1 == t {
        for (i = 2; i <= NF; i++) {
          split($i, a, "=")
          if (a[1] == r) { print a[2]; exit }
        }
      }' /proc/pressure/${resource}
  '';

  samplerScript = pkgs.writeShellScript "host-health-sampler" ''
    set -euo pipefail

    OUT="${textfileDir}/host_health.prom"
    TMP="$OUT.tmp"
    LOG="${csvLog}"

    mkdir -p "${textfileDir}" /var/log/host-health
    chmod 755 "${textfileDir}"

    PSI_MEM_SOME=$(${readPsiAvg10 "some" "memory"}); PSI_MEM_SOME=''${PSI_MEM_SOME:-0}
    PSI_MEM_FULL=$(${readPsiAvg10 "full" "memory"}); PSI_MEM_FULL=''${PSI_MEM_FULL:-0}
    PSI_CPU_SOME=$(${readPsiAvg10 "some" "cpu"}); PSI_CPU_SOME=''${PSI_CPU_SOME:-0}

    read -r LOAD1 _ _ < /proc/loadavg

    MEM_TOTAL=$(${pkgs.gawk}/bin/gawk '/MemTotal:/ {print $2}' /proc/meminfo)
    MEM_AVAIL=$(${pkgs.gawk}/bin/gawk '/MemAvailable:/ {print $2}' /proc/meminfo)
    SWAP_TOTAL=$(${pkgs.gawk}/bin/gawk '/SwapTotal:/ {print $2}' /proc/meminfo)
    SWAP_FREE=$(${pkgs.gawk}/bin/gawk '/SwapFree:/ {print $2}' /proc/meminfo)

    MEM_USED_KB=$((MEM_TOTAL - MEM_AVAIL))
    SWAP_USED_KB=$((SWAP_TOTAL - SWAP_FREE))

    if [ "$MEM_TOTAL" -gt 0 ]; then
      MEM_USED_RATIO=$(${pkgs.gawk}/bin/gawk -v u="$MEM_USED_KB" -v t="$MEM_TOTAL" 'BEGIN {printf "%.6f", u/t}')
    else
      MEM_USED_RATIO=0
    fi

    if [ "$SWAP_TOTAL" -gt 0 ]; then
      SWAP_USED_RATIO=$(${pkgs.gawk}/bin/gawk -v u="$SWAP_USED_KB" -v t="$SWAP_TOTAL" 'BEGIN {printf "%.6f", u/t}')
    else
      SWAP_USED_RATIO=0
    fi

    LOAD_RATIO=$(${pkgs.gawk}/bin/gawk -v l="$LOAD1" -v c="${toString cpuCores}" 'BEGIN {printf "%.6f", l/c}')

    TEMP_RAW=$(${pkgs.coreutils}/bin/cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)
    if [ -n "''${TEMP_RAW:-}" ]; then
      TEMP=$(${pkgs.gawk}/bin/gawk -v t="''${TEMP_RAW}" 'BEGIN {printf "%.1f", t/1000}')
    else
      TEMP=0
    fi

    FFMPEG=$(${pkgs.coreutils}/bin/pgrep -c ffmpeg 2>/dev/null || echo 0)

    {
      echo '# HELP q958_psi_memory_some_avg10 Memory PSI some avg10 (0-100)'
      echo '# TYPE q958_psi_memory_some_avg10 gauge'
      echo "q958_psi_memory_some_avg10 $PSI_MEM_SOME"
      echo '# HELP q958_psi_memory_full_avg10 Memory PSI full avg10 (0-100)'
      echo '# TYPE q958_psi_memory_full_avg10 gauge'
      echo "q958_psi_memory_full_avg10 $PSI_MEM_FULL"
      echo '# HELP q958_psi_cpu_some_avg10 CPU PSI some avg10 (0-100)'
      echo '# TYPE q958_psi_cpu_some_avg10 gauge'
      echo "q958_psi_cpu_some_avg10 $PSI_CPU_SOME"
      echo '# HELP q958_load_ratio Load1 divided by CPU core count'
      echo '# TYPE q958_load_ratio gauge'
      echo "q958_load_ratio $LOAD_RATIO"
      echo '# HELP q958_memory_used_ratio Fraction of RAM used (1 - MemAvailable/MemTotal)'
      echo '# TYPE q958_memory_used_ratio gauge'
      echo "q958_memory_used_ratio $MEM_USED_RATIO"
      echo '# HELP q958_swap_used_ratio Fraction of swap used'
      echo '# TYPE q958_swap_used_ratio gauge'
      echo "q958_swap_used_ratio $SWAP_USED_RATIO"
      echo '# HELP q958_cpu_package_temp_celsius CPU package temperature'
      echo '# TYPE q958_cpu_package_temp_celsius gauge'
      echo "q958_cpu_package_temp_celsius $TEMP"
      echo '# HELP q958_ffmpeg_processes Active ffmpeg processes (transcodes)'
      echo '# TYPE q958_ffmpeg_processes gauge'
      echo "q958_ffmpeg_processes $FFMPEG"

      echo '# HELP q958_service_rss_bytes RSS of tracked systemd services'
      echo '# TYPE q958_service_rss_bytes gauge'
      for svc in ${lib.concatStringsSep " " trackedServices}; do
        unit="''${svc}.service"
        mem=$(${pkgs.systemd}/bin/systemctl show "$unit" -p MemoryCurrent --value 2>/dev/null || true)
        if [ -n "''${mem:-}" ] && [ "$mem" != "[not set]" ] && [ "$mem" != "0" ]; then
          echo "q958_service_rss_bytes{service=\"$svc\"} $mem"
        fi
      done

      echo '# HELP q958_user_rss_bytes RSS sum per login user (AI sessions, AMP, …)'
      echo '# TYPE q958_user_rss_bytes gauge'
      for user in ${lib.concatStringsSep " " trackedUsers}; do
        rss_kb=$(${pkgs.procps}/bin/ps -u "$user" -o rss= 2>/dev/null | ${pkgs.gawk}/bin/gawk '{s+=$1} END {print s+0}')
        echo "q958_user_rss_bytes{user=\"$user\"} $((rss_kb * 1024))"
      done
    } > "$TMP"
    mv "$TMP" "$OUT"
    chmod 644 "$OUT"

    if [ ! -f "$LOG" ]; then
      echo "timestamp,load1,load_ratio,mem_used_kb,mem_avail_kb,swap_used_kb,swap_total_kb,psi_mem_some,psi_mem_full,psi_cpu_some,temp_c,ffmpeg,moritz_rss_kb" > "$LOG"
    fi
    MORITZ_KB=$(${pkgs.procps}/bin/ps -u moritz -o rss= 2>/dev/null | ${pkgs.gawk}/bin/gawk '{s+=$1} END {print s+0}')
    echo "$(date -Is),$LOAD1,$LOAD_RATIO,$MEM_USED_KB,$MEM_AVAIL,$SWAP_USED_KB,$SWAP_TOTAL,$PSI_MEM_SOME,$PSI_MEM_FULL,$PSI_CPU_SOME,$TEMP,$FFMPEG,$MORITZ_KB" >> "$LOG"

    SZ=$(${pkgs.coreutils}/bin/stat -c%s "$LOG" 2>/dev/null || echo 0)
    if [ "$SZ" -gt ${toString csvMaxBytes} ]; then
      ${pkgs.coreutils}/bin/tail -n 8000 "$LOG" > "$LOG.tmp"
      ${pkgs.coreutils}/bin/mv "$LOG.tmp" "$LOG"
    fi
  '';

  dashboardPath = ./dashboards/q958-host-health.json;
in
{
  options.my.observability.hostHealth = {
    enable = lib.mkEnableOption ''
      Langzeit-Host-Health-Tracking: 5-Min-Sampler → Prometheus-Textfile → VictoriaMetrics
      (6 Monate Retention) + CSV-Backup unter /var/log/host-health/metrics.csv.
    '';

    sampleIntervalSec = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Sampler-Intervall in Sekunden (Default 5 Min).";
    };
  };

  config = lib.mkIf (cfg.enable && cfgVM.enable) {
    systemd.tmpfiles.rules = [
      "d ${textfileDir} 0755 node-exporter node-exporter -"
      "d /var/log/host-health 0755 root root -"
    ];

    services.prometheus.exporters.node.extraFlags = lib.mkAfter [
      "--collector.textfile.directory=${textfileDir}"
      "--collector.hwmon"
      "--collector.pressure"
    ];

    systemd.services.host-health-sampler = {
      description = "Sample host memory/PSI/swap metrics for VictoriaMetrics";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${samplerScript}";
        PrivateTmp = true;
        ProtectSystem = true;
        ProtectHome = true;
        ReadWritePaths = [
          textfileDir
          "/var/log/host-health"
        ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    systemd.timers.host-health-sampler = {
      description = "Host-health sampler every ${toString cfg.sampleIntervalSec}s";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString cfg.sampleIntervalSec}s";
        AccuracySec = "30s";
      };
    };

    services.grafana.provision.dashboards.settings = {
      apiVersion = 1;
      providers = [
        {
          name = "q958-host-health";
          folder = "q958";
          type = "file";
          disableDeletion = false;
          options.path = dashboardPath;
        }
      ];
    };
  };
}