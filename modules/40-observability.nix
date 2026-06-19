
# ==============================================================================
# PURPOSE
# ==============================================================================
# Consolidates all system observability components:
# 1. Gatus Health Monitoring and Dynamic Endpoints.
# 2. Vector, Loki, and Grafana (VLG) Log Scraper and Dashboard Stack.
# 3. CrowdSec Security Threat Detection Engine and nftables Bouncer.

{ config, lib, pkgs, ... }:

let
  cfgGatus = config.my.services.gatus;
  cfgObs = config.my.observability;
  cfgCrowdsec = config.my.security.crowdsec;
  domain = config.my.configs.identity.domain;

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my = {
    services.gatus = {
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

    observability = {
      enable = lib.mkEnableOption "Vector + Loki + Grafana centralized logging stack";
      lokiPort = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.loki;
        description = "Port for the Loki API server.";
      };
      grafanaPort = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.grafana;
        description = "Port for the Grafana web dashboard.";
      };
    };

    security.crowdsec = {
      enable = lib.mkEnableOption "CrowdSec security engine and nftables firewall bouncer";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ─── SECTION 1: GATUS MONITORING ──────────────────────────────────────────
    (lib.mkIf cfgGatus.enable {

      users.users.monitoring = {
        isSystemUser = true;
        group = "media";
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
        (pkgs.writeShellScriptBin "check-fast-pool" ''
          set -euo pipefail
          POOL_MOUNT="/mnt/fast_pool"
          MOUNTPOINT="${pkgs.util-linux}/bin/mountpoint"

          if ! "$MOUNTPOINT" -q "$POOL_MOUNT"; then
            echo "ERROR: MergerFS pool '$POOL_MOUNT' is not mounted!"
            exit 2
          fi

          shopt -s nullglob
          mounted_branches=0
          for dir in "/mnt/tier-b"/*; do
            if [ -d "$dir" ] && "$MOUNTPOINT" -q "$dir"; then
              mounted_branches=$((mounted_branches + 1))
            fi
          done

          if [ "$mounted_branches" -eq 0 ]; then
            echo "ERROR: No branches are mounted under /mnt/tier-b!"
            exit 1
          fi

          echo "OK: Pool 'fast_pool' is healthy with $mounted_branches active branches."
          exit 0
        '')
        (pkgs.writeShellScriptBin "check-media-pool" ''
          set -euo pipefail
          POOL_MOUNT="/mnt/media"
          MOUNTPOINT="${pkgs.util-linux}/bin/mountpoint"

          if ! "$MOUNTPOINT" -q "$POOL_MOUNT"; then
            echo "ERROR: MergerFS pool '$POOL_MOUNT' is not mounted!"
            exit 2
          fi

          shopt -s nullglob
          mounted_branches=0
          for dir in "/mnt/tier-c"/*; do
            if [ -d "$dir" ] && "$MOUNTPOINT" -q "$dir"; then
              mounted_branches=$((mounted_branches + 1))
            fi
          done

          if [ "$mounted_branches" -eq 0 ]; then
            echo "ERROR: No branches are mounted under /mnt/tier-c!"
            exit 1
          fi

          echo "OK: Pool 'media' is healthy with $mounted_branches active branches."
          exit 0
        '')
        (pkgs.writeShellScriptBin "check-external-pool" ''
          set -euo pipefail
          POOL_MOUNT="/mnt/external_pool"
          MOUNTPOINT="${pkgs.util-linux}/bin/mountpoint"

          if ! "$MOUNTPOINT" -q "$POOL_MOUNT"; then
            echo "ERROR: MergerFS pool '$POOL_MOUNT' is not mounted!"
            exit 2
          fi

          shopt -s nullglob
          mounted_branches=0
          for dir in "/mnt/external"/*; do
            if [ -d "$dir" ] && "$MOUNTPOINT" -q "$dir"; then
              mounted_branches=$((mounted_branches + 1))
            fi
          done

          if [ "$mounted_branches" -eq 0 ]; then
            echo "ERROR: No branches are mounted under /mnt/external!"
            exit 1
          fi

          echo "OK: Pool 'external_pool' is healthy with $mounted_branches active branches."
          exit 0
        '')
        (pkgs.writeShellScriptBin "check-permissions-drift" ''
          set -euo pipefail
          drift_detected=0
          shopt -s nullglob
          for dir in "/mnt/tier-b"/* "/mnt/tier-c"/*; do
            [ -d "$dir" ] || continue
            owner=$(stat -c "%u:%g" "$dir")
            perms=$(stat -c "%a" "$dir")
            if [ "$owner" != "0:169" ]; then
              echo "DRIFT: Directory $dir is owned by $owner, expected 0:169"
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
          if [ -S "/run/redis-valkey/valkey.sock" ]; then
            response=$(${pkgs.valkey}/bin/valkey-cli -s /run/redis-valkey/valkey.sock ping)
            if [ "$response" = "PONG" ]; then
              echo "OK: Valkey socket is responding with PONG"
              exit 0
            fi
          fi
          echo "ERROR: Valkey socket not responding"
          exit 1
        '')
        (pkgs.writeShellScriptBin "check-forgejo-uds" ''
          set -euo pipefail
          if ${pkgs.curl}/bin/curl -fsS --unix-socket /run/forgejo/forgejo.sock http://localhost/api/v1/version >/dev/null; then
            echo "OK: Forgejo socket is responding"
            exit 0
          else
            echo "ERROR: Forgejo socket not responding"
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
            web.port = cfgGatus.port;
          };
        };

        caddy.virtualHosts."gatus.${domain}" = {
          extraConfig = ''
            import tailscale_admin
            import sso_auth
            reverse_proxy 127.0.0.1:${toString cfgGatus.port}
          '';
        };
      };

      systemd.services.gatus = {
        preStart = lib.mkAfter ''
          if [ -f /home/moritz/secrets/gatus_ssh_key ]; then
            install -D -m 600 -o gatus -g gatus /home/moritz/secrets/gatus_ssh_key /var/lib/gatus/ssh_key
          fi
        '';
        serviceConfig = {
          Environment = lib.mkForce [
            "GATUS_CONFIG_PATH=${cfgGatus.endpointsFile}"
          ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          NoNewPrivileges = true;
          MemoryDenyWriteExecute = true;
          DevicePolicy = "closed";
          CapabilityBoundingSet = [ "CAP_NET_RAW" ];
          AmbientCapabilities = [ "CAP_NET_RAW" ];
          StateDirectory = "gatus";
        };
        after = [ "network.target" ];
      };
    })

    # ─── SECTION 2: OBSERVABILITY (LOKI + VECTOR + GRAFANA) ───────────────────
    (lib.mkIf cfgObs.enable {
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
              http_addr = "127.0.0.1";
              http_port = cfgObs.grafanaPort;
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

        caddy.virtualHosts."grafana.${domain}" = {
          extraConfig = ''
            import tailscale_admin
            import sso_auth
            reverse_proxy 127.0.0.1:${toString cfgObs.grafanaPort}
          '';
        };
      };

      systemd.services = {
        loki.serviceConfig = {
          ProtectSystem = lib.mkForce "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          NoNewPrivileges = true;
          MemoryDenyWriteExecute = true;
          DevicePolicy = "closed";
          CapabilityBoundingSet = "";
          ReadWritePaths = [ "/var/lib/loki" ];
        };

        vector = {
          serviceConfig = {
            StateDirectory = "vector";
            StateDirectoryMode = "0750";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            NoNewPrivileges = true;
            MemoryDenyWriteExecute = true;
            DevicePolicy = "closed";
            CapabilityBoundingSet = "";
            ReadWritePaths = [ "/var/lib/vector" ];
          };
        };

        grafana = {
          preStart = lib.mkAfter ''
            if [ -f /home/moritz/secrets/grafana_secret_key ]; then
              install -D -m 600 -o grafana -g grafana /home/moritz/secrets/grafana_secret_key /var/lib/grafana/secret_key
            fi
          '';
          serviceConfig = {
            ProtectSystem = lib.mkForce "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            NoNewPrivileges = true;
            MemoryDenyWriteExecute = true;
            DevicePolicy = "closed";
            CapabilityBoundingSet = "";
            ReadWritePaths = [ "/var/lib/grafana" ];
            EnvironmentFile = "-/home/moritz/secrets/grafana.env";
          };
        };
      };
    })

    # ─── SECTION 3: CROWDSEC SECURITY ─────────────────────────────────────────
    (lib.mkIf cfgCrowdsec.enable {
      services.crowdsec = {
        enable = true;
        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
          "crowdsecurity/caddy"
        ];
        localConfig.acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
            labels.type = "sshd";
          }
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=caddy.service" ];
            labels.type = "caddy";
          }
        ];
        settings = {
          general.api.server = {
            enable = true;
            listen_uri = "127.0.0.1:8080";
          };
          lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
        };
      };

      systemd.services.crowdsec.serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/crowdsec" ];
      };

      services.crowdsec-firewall-bouncer = {
        enable = true;
        registerBouncer.enable = false;
        secrets.apiKeyPath = "/home/moritz/secrets/crowdsec_bouncer_key";
        settings = {
          api_url = "http://127.0.0.1:8080/";
          mode = "nftables";
          nftables = {
            ipv4_set_name = "crowdsec_blocked_ipv4";
            ipv6_set_name = "crowdsec_blocked_ipv6";
            table = "inet filter";
            chain = "input";
          };
        };
      };

      systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      };
    })
  ];
}

