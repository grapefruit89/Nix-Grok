# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Lidarr + Readarr on-demand (socket-proxyd + idle-stop)
#   docs:
#     - docs/adr/5033-systemd-socket-on-demand.md
#   tags:
#     - media
#     - arr
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
    idleTimeoutSec = cfg.idleTimeoutSec;
  };
  memory = import ../../lib/memory-policy.nix {
    inherit lib;
    ramGB = config.my.configs.hardware.ramGB;
  };
  ports = config.my.ports;
  svc = config.my.services;

  mkArrOnDemand =
    {
      name,
      publicPort,
      metadataDir,
      extraEnv,
    }:
    let
      iPort = onDemand.internalPort publicPort;
      nameUpper = lib.toUpper name;
      dataDir = "/var/lib/${name}";
      package = config.services.${name}.package;
    in
    lib.mkIf (cfg.enable && svc.${name}.enable) (
      lib.mkMerge [
        (onDemand.mkProxy { inherit name publicPort; })
        (onDemand.mkIdleStop { inherit name publicPort; })
        {
          services.${name}.settings.server.port = lib.mkForce iPort;

          systemd.services."${name}-backend" = {
            description = "${name} (on-demand backend)";
            after = [ "network.target" ];
            wantedBy = lib.mkForce [ ];
            environment = {
              "${nameUpper}__AUTH__METHOD" = "External";
              "${nameUpper}__LOG__ANALYTICSENABLED" = "false";
              "${nameUpper}__LOG__LEVEL" = "info";
              "${nameUpper}__SERVER__PORT" = toString iPort;
              "${nameUpper}__UPDATE__AUTOMATICALLY" = "false";
              "${nameUpper}__UPDATE__MECHANISM" = "external";
            }
            // extraEnv;
            serviceConfig = lib.mkMerge [
              (memory.arr { })
              {
                ExecStart = "${lib.getExe package} -nobrowser -data='${dataDir}'";
                User = name;
                Group = name;
                UMask = "0002";
                EnvironmentFile = [ "/var/lib/secrets/${name}.env" ];
                BindPaths = [ "${metadataDir}:${dataDir}/MediaCover" ];
                ReadWritePaths = [
                  dataDir
                  "/data/downloads"
                  "/data/media"
                ];
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
                LockPersonality = true;
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                SystemCallFilter = [
                  "@system-service"
                  "~@privileged"
                ];
              }
            ];
          };
        }
      ]
    );
in
{
  config = lib.mkMerge [
    (mkArrOnDemand {
      name = "lidarr";
      publicPort = ports.lidarr;
      metadataDir = "/mnt/fast_pool/metadata/lidarr";
      extraEnv = {
        LIDARR__UPDATE__BRANCH = "master";
      };
    })
    (mkArrOnDemand {
      name = "readarr";
      publicPort = ports.readarr;
      metadataDir = "/mnt/fast_pool/metadata/readarr";
      extraEnv = {
        READARR__UPDATE__BRANCH = "develop";
      };
    })
  ];
}