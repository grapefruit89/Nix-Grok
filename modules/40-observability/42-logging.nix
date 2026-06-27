# ---
# meta:
#   id: NIXH-42-MOD-001
#   layer: 3
#   role: module
#   purpose: Loki + Vector + Grafana — zentrales Logging- und Dashboarding-Stack
#   lib:
#     - lib/memory-policy.nix
#     - lib/unix-sockets.nix
#     - lib/systemd-hardening.nix
#   services:
#     - loki
#     - vector
#     - grafana
#   tags:
#     - observability
#     - logging
#     - grafana
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgObs = config.my.observability;
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  sockets = import ../../lib/unix-sockets.nix { inherit lib; };
  hardening = import ../../lib/systemd-hardening.nix { inherit lib; };
  domain = config.my.configs.identity.domain;
in
{
  options.my.observability = {
    enable = lib.mkEnableOption "Vector + Loki + Grafana centralized logging stack";
    lokiPort = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.loki;
      description = "Port for the Loki API server.";
    };
  };

  config = lib.mkIf cfgObs.enable {
    services = {
      loki = {
        enable = true;
        configFile = pkgs.writeText "loki-config.yaml" ''
          auth_enabled: false
          server:
            http_listen_port: ${toString cfgObs.lokiPort}
            grpc_listen_port: 9095
          common:
            instance_addr: 127.0.0.1
            path_prefix: /var/lib/loki
            storage:
              filesystem:
                chunks_directory: /var/lib/loki/chunks
                rules_directory: /var/lib/loki/rules
            replication_factor: 1
            ring:
              kvstore:
                store: inmemory
          limits_config:
            reject_old_samples: true
            reject_old_samples_max_age: 168h
            creation_grace_period: 10m
            retention_period: 168h
          compactor:
            working_directory: /var/lib/loki/compactor
            compaction_interval: 10m
            retention_enabled: true
            retention_delete_delay: 2h
            retention_delete_worker_count: 150
            delete_request_store: filesystem
          schema_config:
            configs:
              - from: 2026-01-01
                store: tsdb
                object_store: filesystem
                schema: v13
                index:
                  prefix: index_
                  period: 24h
        '';
      };

      vector = {
        enable = true;
        journaldAccess = true;
        settings = {
          sources = {
            journald_source = {
              type = "journald";
              exclude_units = [ "vector.service" ];
            };
          };
          transforms = {
            caddy_parse = {
              type = "remap";
              inputs = [ "journald_source" ];
              source = ''
                if .SYSLOG_IDENTIFIER == "caddy" {
                  parsed, err = parse_json(.message)
                  if err == null {
                    .caddy = parsed
                    .source = "caddy"
                    status, serr = to_int(.caddy.status)
                    .level = if serr == null && status >= 500 { "error" } else if serr == null && status >= 400 { "warn" } else { "info" }
                  } else {
                    .source = "caddy-system"
                    .level = "info"
                  }
                } else {
                  ident = to_string(.SYSLOG_IDENTIFIER) ?? "system"
                  .source = downcase(ident)
                  pri, perr = to_int(.PRIORITY)
                  .level = if perr == null && pri <= 3 { "error" } else if perr == null && pri <= 5 { "warn" } else { "info" }
                }
                .host = "${config.networking.hostName}"
              '';
            };
          };
          sinks = {
            loki_sink = {
              type = "loki";
              inputs = [ "caddy_parse" ];
              endpoint = "http://127.0.0.1:${toString cfgObs.lokiPort}";
              encoding.codec = "json";
              labels = {
                source = "{{ source }}";
                level = "{{ level }}";
                host = "{{ host }}";
              };
            };
          };
        };
      };

      grafana = {
        enable = true;
        settings = {
          server = {
            protocol = "socket";
            socket = sockets.grafana;
            socket_mode = "0666";
            domain = "grafana.${domain}";
          };
          security = {
            secret_key = "$__file{/var/lib/grafana/secret_key}";
          };
        };
        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:${toString cfgObs.lokiPort}";
              isDefault = true;
            }
          ];
        };
      };
    };

    systemd.services = {
      loki.serviceConfig = lib.mkMerge [
        (memory.loki { })
        (hardening.mkHardened { rw = [ "/var/lib/loki" ]; })
        {
          ProtectSystem = lib.mkForce "strict";
          CapabilityBoundingSet = "";
        }
      ];

      vector = {
        after = [ "loki.service" ];
        serviceConfig = lib.mkMerge [
          (memory.vector { })
          (hardening.mkHardened { rw = [ "/var/lib/vector" ]; })
          {
            StateDirectory = "vector";
            StateDirectoryMode = "0750";
            CapabilityBoundingSet = "";
          }
        ];
      };

      grafana = {
        preStart = lib.mkAfter ''
          if [ -f /var/lib/secrets/grafana_secret_key ]; then
            install -D -m 600 -o grafana -g grafana /var/lib/secrets/grafana_secret_key /var/lib/grafana/secret_key
          fi
        '';
        serviceConfig = lib.mkMerge [
          (memory.grafana { })
          (hardening.mkHardened { rw = [ "/var/lib/grafana" ]; })
          {
            ProtectSystem = lib.mkForce "strict";
            CapabilityBoundingSet = "";
            EnvironmentFile = "-/var/lib/secrets/grafana.env";
          }
        ];
      };
    };
  };
}
