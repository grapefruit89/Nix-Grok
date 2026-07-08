# ---
# meta:
#   layer: 3
#   role: module
#   purpose: SABnzbd Usenet — VPN-Sandbox via 57-usenet-confinement
#   docs:
#     - docs/memory_oom.md
#     - docs/adr/5031-usenet-vpn-sandbox.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - sabnzbd
#   tags:
#     - media
#     - usenet
# ---
{
  config,
  lib,
  ...
}:
let
  memory = import ../../lib/memory-policy.nix {
    inherit lib;
    ramGB = config.my.configs.hardware.ramGB;
  };
  cfgSabnzbd = config.my.services.sabnzbd;
  portSabnzbd = config.my.ports.sabnzbd;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;
in
{
  config = lib.mkIf cfgSabnzbd.enable {
    my.impermanence.extraPaths = [ "/var/lib/sabnzbd" ];

    services.sabnzbd = {
      enable = true;
      openFirewall = false;
      configFile = null;
      allowConfigWrite = true;
      settings = {
        misc = {
          port = portSabnzbd;
          host = "127.0.0.1";
          language = config.my.configs.locale.language;
        };
      };
    };

    users = {
      groups = {
        media = { };
        sabnzbd.gid = lib.mkForce gids.sabnzbd;
      };
      users.sabnzbd = {
        uid = lib.mkForce uids.sabnzbd;
        extraGroups = [ "media" ];
      };
    };

    systemd.services.sabnzbd.serviceConfig = lib.mkMerge [
      (memory.sabnzbd { })
      {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        UMask = "0002";
        RuntimeDirectory = "sabnzbd-tmp";
        RuntimeDirectoryMode = "0700";
        ReadWritePaths = [
          "/var/lib/sabnzbd"
          "/data/downloads"
          "/run/sabnzbd-tmp"
        ];
      }
    ];

    systemd.services.sabnzbd.environment = {
      SABNZBD__MISC__TEMP_DIR = "/run/sabnzbd-tmp";
    };
  };
}
