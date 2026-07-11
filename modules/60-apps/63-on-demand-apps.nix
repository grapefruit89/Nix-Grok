# ---
# meta:
#   layer: 3
#   role: module
#   purpose: On-demand socket activation — Shiori, Libreseerr, Filebrowser, Open WebUI
#   docs:
#     - docs/adr/5033-systemd-socket-on-demand.md
#   services:
#     - shiori
#     - libreseerr
#     - filebrowser
#     - open-webui
#   tags:
#     - apps
#     - on-demand
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.policy.onDemand;
  onDemand = import ../../lib/on-demand-http.nix {
    inherit lib pkgs;
    internalOffset = cfg.internalOffset;
  };

  svc = config.my.services;
  ports = config.my.ports;

  mkBackend =
    {
      name,
      unit,
    }:
    let
      backendUnit = "${name}-backend";
    in
    {
      systemd.services.${backendUnit} = lib.mkMerge [
        unit
        { wantedBy = lib.mkForce [ ]; }
      ];
    };

  mkWrapped =
    {
      name,
      enable,
      publicPort,
      backend,
    }:
    lib.mkIf (cfg.enable && enable) (
      lib.mkMerge [
        (onDemand.mkProxy { inherit name publicPort; })
        backend
      ]
    );
in
{
  config = lib.mkMerge [
    (mkWrapped {
      name = "shiori";
      enable = svc.shiori.enable;
      publicPort = ports.shiori;
      backend =
        let
          shioriCfg = config.services.shiori;
          iPort = onDemand.internalPort ports.shiori;
        in
        lib.mkMerge [
          {
            services.shiori.port = lib.mkForce iPort;

            systemd.services.shiori-secret-init = {
              before = lib.mkForce [ "shiori-backend.service" ];
              wantedBy = lib.mkForce [ "shiori-backend.service" ];
            };
          }
          (mkBackend {
            name = "shiori";
            unit = {
              description = "Shiori bookmarks (on-demand backend)";
              after = [
                "network.target"
                "shiori-secret-init.service"
              ];
              environment = {
                SHIORI_DIR = "/var/lib/shiori";
              };
              serviceConfig = {
                ExecStart = "${shioriCfg.package}/bin/shiori server --address '127.0.0.1' --port '${toString iPort}' --webroot '/'";
                DynamicUser = true;
                StateDirectory = "shiori";
                RuntimeDirectory = "shiori";
                EnvironmentFile = lib.optional (shioriCfg.environmentFile != null) shioriCfg.environmentFile;
                BindReadOnlyPaths = [
                  "/nix/store"
                  "/etc"
                ];
                CapabilityBoundingSet = "";
                DeviceAllow = "";
                LockPersonality = true;
                MemoryDenyWriteExecute = true;
                PrivateDevices = true;
                PrivateUsers = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                RestrictNamespaces = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                RootDirectory = "/run/shiori";
                SystemCallArchitectures = "native";
                SystemCallErrorNumber = "EPERM";
                SystemCallFilter = [
                  "@system-service"
                  "~@cpu-emulation"
                  "~@debug"
                  "~@keyring"
                  "~@memlock"
                  "~@obsolete"
                  "~@privileged"
                  "~@setuid"
                ];
              };
            };
          })
        ];
    })

    (mkWrapped {
      name = "filebrowser";
      enable = svc.filebrowser.enable;
      publicPort = ports.filebrowser;
      backend =
        let
          fbCfg = config.services.filebrowser;
          iPort = onDemand.internalPort ports.filebrowser;
          fbArgs =
            let
              args = [
                (lib.getExe fbCfg.package)
                "--address"
                "127.0.0.1"
                "--port"
                (toString iPort)
                "--root"
                fbCfg.settings.root
                "--database"
                fbCfg.settings.database
                "--cache-dir"
                fbCfg.settings.cache-dir
              ];
            in
            lib.concatStringsSep " " args;
        in
        lib.mkMerge [
          { services.filebrowser.settings.port = lib.mkForce iPort; }
          (mkBackend {
            name = "filebrowser";
            unit = {
              description = "Filebrowser (on-demand backend)";
              after = [ "network.target" ];
              serviceConfig = {
                ExecStart = fbArgs;
                User = fbCfg.user;
                Group = fbCfg.group;
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                OOMScoreAdjust = 300;
                CapabilityBoundingSet = "";
                RestrictNamespaces = true;
                ProtectClock = true;
                ProtectHostname = true;
                LockPersonality = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                ReadWritePaths = [
                  "/var/lib/filebrowser"
                  svc.filebrowser.rootPath
                ];
              };
            };
          })
        ];
    })

    (mkWrapped {
      name = "open-webui";
      enable = svc.open-webui.enable;
      publicPort = ports.open-webui;
      backend =
        let
          owCfg = config.services.open-webui;
          iPort = onDemand.internalPort ports.open-webui;
        in
        lib.mkMerge [
          { services.open-webui.port = lib.mkForce iPort; }
          (mkBackend {
            name = "open-webui";
            unit = {
              description = "Open WebUI (on-demand backend)";
              after = [ "network.target" ];
              environment = {
                STATIC_DIR = "${owCfg.stateDir}/static";
                DATA_DIR = "${owCfg.stateDir}/data";
                HF_HOME = "${owCfg.stateDir}/hf_home";
                SENTENCE_TRANSFORMERS_HOME = "${owCfg.stateDir}/transformers_home";
                WEBUI_URL = "http://localhost:${toString iPort}";
              }
              // owCfg.environment;
              preStart = ''
                if [ -d "${owCfg.stateDir}/data" ] && [ -n "$(ls -A "${owCfg.stateDir}/data" 2>/dev/null)" ]; then
                  exit 0
                fi
                mkdir -p "${owCfg.stateDir}/data"
                [ -f "${owCfg.stateDir}/webui.db" ] && mv "${owCfg.stateDir}/webui.db" "${owCfg.stateDir}/data/"
                for dir in cache uploads vector_db; do
                  [ -d "${owCfg.stateDir}/$dir" ] && mv "${owCfg.stateDir}/$dir" "${owCfg.stateDir}/data/"
                done
                exit 0
              '';
              serviceConfig = {
                ExecStart = "${lib.getExe owCfg.package} serve --host \"127.0.0.1\" --port ${toString iPort}";
                EnvironmentFile = lib.optional (owCfg.environmentFile != null) owCfg.environmentFile;
                StateDirectory = "open-webui";
                WorkingDirectory = owCfg.stateDir;
                DynamicUser = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                PrivateDevices = true;
                SupplementaryGroups = [
                  "render"
                  "video"
                ];
                SystemCallFilter = [
                  "@system-service"
                  "~@privileged"
                ];
                OOMScoreAdjust = 200;
              };
            };
          })
        ];
    })

    (mkWrapped {
      name = "libreseerr";
      enable = svc.libreseerr.enable;
      publicPort = ports.libreseerr;
      backend =
        let
          iPort = onDemand.internalPort ports.libreseerr;
          package = pkgs.callPackage ../../packages/libreseerr { };
        in
        lib.mkMerge [
          (mkBackend {
            name = "libreseerr";
            unit = {
              description = "Libreseerr (on-demand backend)";
              after = [ "network.target" ];
              environment = {
                LIBRESEERR_BIND = "127.0.0.1:${toString iPort}";
                DATA_DIR = "/var/lib/libreseerr/data";
              };
              serviceConfig = {
                Type = "simple";
                User = "libreseerr";
                Group = "libreseerr";
                StateDirectory = "libreseerr";
                WorkingDirectory = "/var/lib/libreseerr/data";
                ExecStart = "${package}/bin/libreseerr";
                Restart = "on-failure";
                RestartSec = "10s";
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                ReadWritePaths = [ "/var/lib/libreseerr" ];
              };
            };
          })
        ];
    })
  ];
}
