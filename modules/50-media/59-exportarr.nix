# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Prometheus Exportarr exporters for *arr services
#   tags:
#     - media
#     - observability
#     - prometheus
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media.exporters;
  ports = config.my.ports;
  secretsDir = "/var/lib/secrets";
  vmEnabled = config.my.observability.victoriametrics.enable;
  tr = "${pkgs.coreutils}/bin/tr";
  grep = "${pkgs.gnugrep}/bin/grep";

  keyValidator = pkgs.writeShellScript "exportarr-key-valid" ''
    set -euo pipefail
    key=$(${tr} -d ' \n\r\t-' < "$1")
    len=''${#key}
    [ "$len" -ge 20 ] && [ "$len" -le 32 ] && printf '%s' "$key" | ${grep} -qE '^[a-zA-Z0-9]+$'
  '';

  mkWrapper =
    service: arrPort: exporterPort:
    pkgs.writeShellScript "exportarr-${service}-wrapper" ''
      set -euo pipefail
      key=$(${tr} -d ' \n\r\t-' < "''${CREDENTIALS_DIRECTORY}/api-key")
      exec ${pkgs.exportarr}/bin/exportarr ${service} \
        --url "http://127.0.0.1:${toString arrPort}" \
        --api-key "$key" \
        --port ${toString exporterPort} \
        --interface 127.0.0.1
    '';

  mkExporter =
    {
      service,
      portOption,
      arrPort,
      apiKeyFile,
    }:
    let
      exporterPort = ports.${portOption};
      wrapper = mkWrapper service arrPort exporterPort;
    in
    lib.mkIf (config.my.services.${service}.enable && cfg.enable) {
      systemd.services."prometheus-exportarr-${service}-exporter" = {
        description = "Prometheus Exportarr exporter for ${service}";
        after = [
          "${service}.service"
          "arr-sync-keys.service"
          "network.target"
        ];
        wants = [ "${service}.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          User = "exportarr-${service}-exporter";
          Group = "exportarr-${service}-exporter";
          LoadCredential = [ "api-key:${apiKeyFile}" ];
          ExecCondition = "${keyValidator} %d/api-key";
          ExecStart = wrapper;
          Restart = "always";
          RestartSec = "10s";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          IPAddressAllow = [
            "localhost"
            "127.0.0.0/8"
            "::1/128"
          ];
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          UMask = "0077";
          WorkingDirectory = "/tmp";
        };
      };
    };

  scrapeTargets = lib.flatten (
    lib.mapAttrsToList
      (
        service: portOption:
        lib.optional (config.my.services.${service}.enable && cfg.enable) {
          job_name = "exportarr-${service}";
          static_configs = [
            { targets = [ "127.0.0.1:${toString ports.${portOption}}" ]; }
          ];
          scrape_interval = "30s";
        }
      )
      (
        {
          sonarr = "exportarr-sonarr";
          radarr = "exportarr-radarr";
          prowlarr = "exportarr-prowlarr";
        }
        // lib.optionalAttrs (config.my.services.lidarr.enable && cfg.lidarr.enable) {
          lidarr = "exportarr-lidarr";
        }
      )
  );
in
{
  options.my.media.exporters = {
    enable = lib.mkEnableOption "Prometheus Exportarr exporters for enabled *arr services";
    lidarr.enable = lib.mkEnableOption "Exportarr for Lidarr (requires lidarr_api_key in secrets)";
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.services.sonarr.enable || config.my.services.radarr.enable) {
      my.media.exporters.enable = lib.mkDefault vmEnabled;
    })
    (mkExporter {
      service = "sonarr";
      portOption = "exportarr-sonarr";
      arrPort = ports.sonarr;
      apiKeyFile = "${secretsDir}/sonarr_api_key";
    })
    (mkExporter {
      service = "radarr";
      portOption = "exportarr-radarr";
      arrPort = ports.radarr;
      apiKeyFile = "${secretsDir}/radarr_api_key";
    })
    (mkExporter {
      service = "prowlarr";
      portOption = "exportarr-prowlarr";
      arrPort = ports.prowlarr;
      apiKeyFile = "${secretsDir}/prowlarr_api_key";
    })
    (lib.mkIf (config.my.services.lidarr.enable && cfg.lidarr.enable) (mkExporter {
      service = "lidarr";
      portOption = "exportarr-lidarr";
      arrPort = ports.lidarr;
      apiKeyFile = "${secretsDir}/lidarr_api_key";
    }))
    (lib.mkIf (vmEnabled && cfg.enable && scrapeTargets != [ ]) {
      services.victoriametrics.prometheusConfig.scrape_configs = lib.mkAfter scrapeTargets;
    })
  ];
}
