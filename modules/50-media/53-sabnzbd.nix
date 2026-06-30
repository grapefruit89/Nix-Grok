# ---
# meta:
#   layer: 3
#   role: module
#   purpose: SABnzbd Usenet mit VPN-Kill-Switch
#   docs:
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#     - lib/vpn-killswitch.nix
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
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  vpnConn = import ../../lib/vpn-connection.nix { inherit lib; };
  cfgSabnzbd = config.my.services.sabnzbd;
  vpnCfg = config.my.services.vpn-confinement;
  portSabnzbd = config.my.ports.sabnzbd;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;
  sabInVpn = vpnConn.isVpnConfined vpnCfg "sabnzbd";
  vpnKillSwitch = import ../../lib/vpn-killswitch.nix {
    inherit lib;
    privadoEnabled = config.my.services.privado-vpn.enable or false;
  };
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
          host = if sabInVpn then "0.0.0.0" else "127.0.0.1";
          # Sprache aus Nix SSoT — arr-sync-locale überschreibt ini bei Abweichung
          language = config.my.configs.locale.language;
        };
      };
    };

    # GID/UID und Gruppen-Anpassung
    users = {
      groups = {
        media = { };
        sabnzbd.gid = lib.mkDefault gids.sabnzbd;
      };
      users.sabnzbd = {
        uid = lib.mkDefault uids.sabnzbd;
        extraGroups = [ "media" ];
      };
    };

    systemd.services.sabnzbd = lib.mkMerge [
      (lib.mkIf (!(config.my.services.vpn-confinement.enable or false)) vpnKillSwitch)
      {
        serviceConfig = lib.mkMerge [
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
        environment = {
          SABNZBD__MISC__TEMP_DIR = "/run/sabnzbd-tmp";
        };
      }
    ];
  };
}
