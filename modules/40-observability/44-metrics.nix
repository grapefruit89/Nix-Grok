# ---
# meta:
#   id: NIXH-44-MOD-001
#   layer: 3
#   role: module
#   purpose: VictoriaMetrics TSDB + Prometheus Node-Exporter
#   services:
#     - victoriametrics
#     - prometheus-node-exporter
#   tags:
#     - observability
#     - metrics
#     - victoriametrics
#     - prometheus
# ---
{
  config,
  lib,
  ...
}:
let
  cfgVM = config.my.observability.victoriametrics;
in
{
  options.my.observability.victoriametrics = {
    enable = lib.mkEnableOption "VictoriaMetrics TSDB (Prometheus-kompatibel)";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.victoriametrics;
      description = "VictoriaMetrics listen port.";
    };
  };

  config = lib.mkIf cfgVM.enable {
    services = {
      victoriametrics = {
        enable = true;
        listenAddress = "127.0.0.1:${toString cfgVM.port}";
        retentionPeriod = "6";
        prometheusConfig = {
          scrape_configs = [
            {
              job_name = "node";
              static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
              scrape_interval = "15s";
            }
            {
              job_name = "victoriametrics";
              static_configs = [ { targets = [ "127.0.0.1:${toString cfgVM.port}" ]; } ];
              scrape_interval = "15s";
            }
          ];
        };
      };

      prometheus.exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9100;
        enabledCollectors = [
          "cpu"
          "diskstats"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "stat"
          "time"
          "uname"
          "vmstat"
          "systemd"
        ];
      };

      grafana.provision.datasources.settings.datasources = lib.mkAfter [
        {
          name = "VictoriaMetrics";
          type = "prometheus";
          url = "http://127.0.0.1:${toString cfgVM.port}";
          access = "proxy";
          isDefault = false;
        }
      ];
    };

    systemd.services.victoriametrics.after = [ "prometheus-node-exporter.service" ];
  };
}
