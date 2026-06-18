
{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgSabnzbd = config.my.services.sabnzbd;
  domain = config.my.configs.identity.domain;
  portSabnzbd = config.my.ports.sabnzbd;
  vpnKillSwitch = import ../../lib/vpn-killswitch.nix {
    inherit lib;
    privadoEnabled = config.my.services.privado-vpn.enable or false;
  };

in
{
  config = lib.mkIf cfgSabnzbd.enable {
    services.sabnzbd = {
      enable = true;
      openFirewall = false;
      configFile = null;
      allowConfigWrite = true;
      settings = {
        misc = {
          port = portSabnzbd;
          host = "127.0.0.1";
        };
      };
    };

    # GID/UID und Gruppen-Anpassung
    users = {
      groups = {
        media = { };
        sabnzbd.gid = lib.mkDefault 194;
      };
      users.sabnzbd = {
        uid = lib.mkDefault 984;
        extraGroups = [ "media" ];
      };
    };

    systemd.services.sabnzbd = lib.mkMerge [
      vpnKillSwitch
      {
        preStart = lib.mkBefore ''
          if [ -f /data/state/sabnzbd/sabnzbd.ini ] && \
             [ "$(grep -c "^\[servers\]" /data/state/sabnzbd/sabnzbd.ini 2>/dev/null || echo 0)" -gt 1 ]; then
            echo "Removing corrupt sabnzbd.ini (duplicate [servers])"
            rm -f /data/state/sabnzbd/sabnzbd.ini
          fi
          
          # RAM-Disk Setup (Incomplete Downloads)
          if [ -f /data/state/sabnzbd/sabnzbd.ini ]; then
            ${pkgs.gnused}/bin/sed -i 's/^download_dir\s*=.*/download_dir = \/run\/sabnzbd-tmp/g' /data/state/sabnzbd/sabnzbd.ini
          fi
        '';
        serviceConfig = {
          ProtectSystem = lib.mkForce "strict";
          ProtectHome = lib.mkForce true;
          PrivateTmp = lib.mkForce true;
          PrivateDevices = lib.mkForce true;
          NoNewPrivileges = lib.mkForce true;
          UMask = "0002";
          RuntimeDirectory = "sabnzbd-tmp";
          RuntimeDirectoryMode = "0700";
          ReadWritePaths = [
            "/data/state/sabnzbd"
            "/data/downloads"
            "/run/sabnzbd-tmp"
          ];
        };
      }
    ];

    services.caddy.virtualHosts."sabnzbd.${domain}" = {
      extraConfig = caddy.proxyTailscaleSso portSabnzbd;
    };
  };
}

