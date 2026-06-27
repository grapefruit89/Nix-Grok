# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Fabrik für *arr-Apps — User, systemd, Caddy, RAM-Limits
#   docs:
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - sonarr
#     - radarr
#     - readarr
#     - prowlarr
#   tags:
#     - media
#     - arr
# ---
{
  config,
  lib,
  ...
}: let
  factory = import ../../lib/service-factory.nix {inherit lib;};
  memory = import ../../lib/memory-policy.nix {inherit lib;};
  vpnKillSwitchAttrs = import ../../lib/vpn-killswitch.nix {
    inherit lib;
    privadoEnabled = config.my.services.privado-vpn.enable or false;
  };
in {
  mkArrService = {
    name,
    port,
    dataDir,
    uid,
    gid,
    useVpnKillSwitch ? false,
    metadataDir ? null,
    upstreamHost ? "127.0.0.1",
  }:
    lib.mkMerge [
      {
        services.${name} = {
          enable = true;
          openFirewall = false;
          inherit dataDir;
        };

        users.groups.${name} = {
          gid = lib.mkDefault gid;
        };
        users.users.${name} = {
          uid = lib.mkDefault uid;
          group = name;
          isSystemUser = true;
          extraGroups = ["media"];
        };
      }

      (factory.mkService {
        inherit config;
        inherit name port upstreamHost;
        mode = "sso";
        hardeningProfile = "dotnet";
        persistDirs = [dataDir];
        readWritePaths = [
          dataDir
          "/data/downloads"
        ];
        readOnlyPaths = ["/data/media"];
        memoryPolicy = memory.arr {};
        extraSystemd = {
          UMask = lib.mkForce "0002";
          BindPaths = lib.mkIf (metadataDir != null) [
            "${metadataDir}:/var/lib/${name}/MediaCover"
          ];
        };
      })

      (lib.mkIf (useVpnKillSwitch && !(config.my.services.vpn-confinement.enable or false)) {
        systemd.services.${name} = vpnKillSwitchAttrs;
      })
    ];
}
