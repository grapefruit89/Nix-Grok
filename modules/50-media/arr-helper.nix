# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Fabrik für *arr-Apps — User, systemd, Caddy, RAM-Limits
#   docs:
#     - docs/adr/007-dendritic-one-file-per-service.md
#     - docs/adr/003-oom-cgroup-isolation.md
#     - docs/adr/011-unified-port-uid-schema.md
#     - docs/guides/GUIDE-media-stack.md
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - sonarr
#     - radarr
#     - readarr
#     - prowlarr
#     - lidarr
#   tags:
#     - media
#     - arr
# ---
{
  config,
  lib,
  ...
}:
let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix {
    inherit lib;
    ramGB = config.my.configs.hardware.ramGB;
  };
in
{
  mkArrService =
    {
      name,
      port,
      dataDir,
      uid,
      gid,
      metadataDir ? null,
      upstreamHost ? "127.0.0.1",
      extraEnv ? { },
      onDemand ? false,
    }:
    let
      nameUpper = lib.strings.toUpper name;
    in
    lib.mkMerge [
      {
        services.${name} = {
          enable = true;
          openFirewall = false;
          inherit dataDir;
          settings.server.port = port;
        };

        users.groups.${name} = {
          gid = lib.mkForce gid;
        };
        users.users.${name} = {
          uid = lib.mkForce uid;
          group = name;
          isSystemUser = true;
          extraGroups = [ "media" ];
        };
      }

      (lib.mkIf (!onDemand) {
        systemd.services.${name}.environment = {
          "${nameUpper}__AUTH__METHOD" = lib.mkForce "External";
          "${nameUpper}__LOG__LEVEL" = lib.mkDefault "info";
        }
        // extraEnv;
      })

      (lib.mkIf (!onDemand) (
        factory.mkService {
          inherit config;
          inherit name port upstreamHost;
          mode = "sso";
          hardeningProfile = "dotnet";
          persistDirs = [ dataDir ];
          readWritePaths = [
            dataDir
            "/data/downloads"
            "/data/media"
          ];
          readOnlyPaths = [ ];
          memoryPolicy = memory.arr { };
          extraSystemd = {
            UMask = lib.mkForce "0002";
            EnvironmentFile = [ "/var/lib/secrets/${name}.env" ];
            BindPaths = lib.mkIf (metadataDir != null) [
              "${metadataDir}:/var/lib/${name}/MediaCover"
            ];
          };
        }
      ))

      (lib.mkIf (metadataDir != null) {
        systemd.tmpfiles.rules = [
          "d ${metadataDir} 0775 ${name} media -"
          "d /var/lib/${name}/MediaCover 0755 ${name} ${name} -"
        ];
      })
    ];
}