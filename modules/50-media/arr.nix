# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Sonarr + Radarr + Readarr + Prowlarr + Lidarr — eine Datei, eine Fabrik (arr-helper.mkArrService)
#   docs:
#     - docs/adr/007-dendritic-one-file-per-service.md
#   services:
#     - sonarr
#     - radarr
#     - readarr
#     - prowlarr
#     - lidarr
#   tags:
#     - media
#     - arr
#     - dendritic
#     - factory
# ---
{
  config,
  lib,
  ...
}:
let
  ports = config.my.ports;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;
  arrHelper = import ./arr-helper.nix { inherit config lib; };
  vpnConn = import ../../lib/vpn-connection.nix { inherit lib; };
  vpnCfg = config.my.services.vpn-confinement;
  prowlarrUpstream = vpnConn.connectionAddress vpnCfg "prowlarr";

  arrApps = {
    sonarr = {
      port = ports.sonarr;
      uid = uids.sonarr;
      gid = gids.sonarr;
      metadataDir = "/mnt/fast_pool/metadata/sonarr";
      extraEnv = {
        SONARR__UPDATE__BRANCH = "main";
      };
    };
    radarr = {
      port = ports.radarr;
      uid = uids.radarr;
      gid = gids.radarr;
      metadataDir = "/mnt/fast_pool/metadata/radarr";
      extraEnv = {
        RADARR__UPDATE__BRANCH = "master";
      };
    };
    readarr = {
      port = ports.readarr;
      uid = uids.readarr;
      gid = gids.readarr;
      metadataDir = "/mnt/fast_pool/metadata/readarr";
      extraEnv = {
        READARR__UPDATE__BRANCH = "develop";
      };
    };
    prowlarr = {
      port = ports.prowlarr;
      uid = uids.prowlarr;
      gid = gids.prowlarr;
      metadataDir = "/mnt/fast_pool/metadata/prowlarr";
      useVpnKillSwitch = true;
      upstreamHost = prowlarrUpstream;
      extraEnv = {
        PROWLARR__UPDATE__BRANCH = "master";
      };
    };
    lidarr = {
      port = ports.lidarr;
      uid = uids.lidarr;
      gid = gids.lidarr;
      metadataDir = "/mnt/fast_pool/metadata/lidarr";
      extraEnv = {
        LIDARR__UPDATE__BRANCH = "master";
      };
    };
  };

  mkArr =
    name: app:
    let
      dataDir = "/var/lib/${name}";
    in
    lib.mkIf config.my.services.${name}.enable (
      arrHelper.mkArrService ({ inherit name dataDir; } // app)
    );
in
{
  config = lib.mkMerge (lib.mapAttrsToList mkArr arrApps);
}
