# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Gatus, Vector/Loki/Grafana, CrowdSec
#   docs:
#     - docs/AUDIT-blocky-caddy-ipv6.md
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - gatus
#     - loki
#     - grafana
#     - vector
#     - crowdsec
#   tags:
#     - observability
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  memory = import ../lib/memory-policy.nix { inherit lib; };
  sockets = import ../lib/unix-sockets.nix { inherit lib; };
  cfgGatus = config.my.services.gatus;
  cfgObs = config.my.observability;
  cfgCrowdsec = config.my.security.crowdsec;
  domain = config.my.configs.identity.domain;
  yaml = pkgs.formats.yaml { };
  gatusLib = import ../lib/gatus-endpoints.nix { inherit lib config; };

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
        (pkgs.writeShellScriptBin "check-forgejo-uds" ''
          set -euo pipefail
          if ${pkgs.curl}/bin/curl -fsS --unix-socket ${sockets.forgejo} http://localhost/api/v1/version >/dev/null; then
            echo "OK: Forgejo socket is responding"
            exit 0
          else
            echo "ERROR: Forgejo socket not responding"
            exit 1
          fi
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
            web.port = cfgGatus.port;
          };
        };

      };

      systemd.services.gatus = {
        preStart = lib.mkAfter ''
          if [ -f /var/lib/secrets/gatus_ssh_key ]; then
            install -D -m 600 -o gatus -g gatus /var/lib/secrets/gatus_ssh_key /var/lib/gatus/ssh_key
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
          {
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
          }
        ];

        vector = {
          serviceConfig = lib.mkMerge [
            (memory.vector { })
            {
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
            {
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
              EnvironmentFile = "-/var/lib/secrets/grafana.env";
            }
          ];
        };
      };
    })

    # ─── SECTION 3: CROWDSEC SECURITY ─────────────────────────────────────────
    (lib.mkIf cfgCrowdsec.enable (
      let
        # cscli in crowdsec-setup liest /etc/crowdsec/config.yaml (ohne -c)
        crowdsecEtcConfig = yaml.generate "crowdsec-etc.yaml" config.services.crowdsec.settings.general;

        crowdsecCredFile = "/var/lib/crowdsec/local_api_credentials.yaml";
        crowdsecCollections = lib.concatMapStringsSep " " lib.escapeShellArg [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
          "crowdsecurity/caddy"
        ];

        crowdsecSetupFixed = pkgs.writeShellScript "crowdsec-setup-fixed" ''
          set -eu
          ${pkgs.coreutils}/bin/mkdir -p /var/lib/crowdsec/state/hub/
          ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml hub update
          ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml collections install ${crowdsecCollections} || true
          ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml machines add ${config.networking.hostName} --auto --force -f "${crowdsecCredFile}"
        '';

        crowdsecPostSetup = pkgs.writeShellScript "crowdsec-post-setup" ''
          _port="${toString config.my.ports.crowdsec}"
          ${pkgs.findutils}/bin/find /var/lib/crowdsec -type f 2>/dev/null | while read -r _f; do
            ${pkgs.gnused}/bin/sed -i \
              -e "s|:8080/|:$_port/|g" \
              -e "s|:8088/|:$_port/|g" \
              -e "s|:8080|:$_port|g" \
              -e "s|:8088|:$_port|g" \
              "$_f" || true
          done
          ${pkgs.coreutils}/bin/rm -rf /var/lib/crowdsec-firewall-bouncer-register 2>/dev/null || true
        '';
      in
      {
        systemd.tmpfiles.rules = [
          "d /etc/crowdsec 0755 root root -"
          "L+ /etc/crowdsec/config.yaml - - - - ${crowdsecEtcConfig}"
          "d /var/lib/crowdsec 0755 root root -"
          "d /var/lib/crowdsec/data 0755 crowdsec crowdsec -"
          "d /var/lib/crowdsec/config 0755 crowdsec crowdsec -"
          "d /var/lib/crowdsec/hub 0755 crowdsec crowdsec -"
        ];

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
              listen_uri = "127.0.0.1:${toString config.my.ports.crowdsec}";
            };
            lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
          };
        };

        systemd.services.crowdsec.serviceConfig = {
          ExecStartPre = lib.mkOverride 50 [
            " "
            crowdsecSetupFixed
            "${lib.getExe' pkgs.crowdsec "crowdsec"} -c /etc/crowdsec/config.yaml -t -error"
            crowdsecPostSetup
          ];
          StateDirectory = "crowdsec";
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
          registerBouncer.enable = true;
          settings = {
            api_url = "http://127.0.0.1:${toString config.my.ports.crowdsec}/";
            mode = "nftables";
            nftables = {
              ipv4_set_name = "crowdsec_blocked_ipv4";
              table = "inet filter";
              chain = "input";
              ipv6.enabled = config.my.security.firewall.ipv6;
            }
            // lib.optionalAttrs config.my.security.firewall.ipv6 {
              ipv6_set_name = "crowdsec_blocked_ipv6";
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
      }
    ))
  ];
}
