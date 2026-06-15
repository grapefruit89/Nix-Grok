
{ config, lib, pkgs, ... }:

let
  cfgSonarr = config.my.services.sonarr;
  cfgRadarr = config.my.services.radarr;
  cfgReadarr = config.my.services.readarr;
  cfgProwlarr = config.my.services.prowlarr;

  ports = config.my.ports;
  arrHelper = import ./arr-helper.nix { inherit config lib pkgs; };

in
{
  config = lib.mkMerge [

    (lib.mkIf cfgSonarr.enable (arrHelper.mkArrService {
      name = "sonarr";
      port = ports.sonarr;
      dataDir = "/var/lib/sonarr";
      uid = 989;
      gid = 989;
    }))


    (lib.mkIf cfgRadarr.enable (arrHelper.mkArrService {
      name = "radarr";
      port = ports.radarr;
      dataDir = "/var/lib/radarr";
      uid = 978;
      gid = 978;
    }))

    (lib.mkIf cfgReadarr.enable (arrHelper.mkArrService {
      name = "readarr";
      port = ports.readarr;
      dataDir = "/var/lib/readarr";
      uid = 987;
      gid = 987;
    }))


    (lib.mkIf cfgProwlarr.enable (arrHelper.mkArrService {
      name = "prowlarr";
      port = ports.prowlarr;
      dataDir = "/var/lib/prowlarr";
      uid = 969; # custom default UID for prowlarr
      gid = 969; # custom default GID for prowlarr
    }))
  ];
}
