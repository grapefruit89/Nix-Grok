/*
---
id: sabnzbd
upstream_repo: "sabnzbd/sabnzbd"
---
*/

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

  netnsName = "sabnzbd-vpn";
  wgIface = "wg0";
  hostVethIp = "10.100.100.1";
  nsVethIp   = "10.100.100.2";

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

    systemd.services."netns-${netnsName}" = {
      description = "SABnzbd WireGuard Network Namespace (Kill-Switch)";
      before = [ "sabnzbd.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        export PATH=${pkgs.iproute2}/bin:${pkgs.wireguard-tools}/bin:$PATH
        ip netns del ${netnsName} 2>/dev/null || true
        ip netns add ${netnsName}
        ip -n ${netnsName} link set lo up
        ip link add veth-sab-host type veth peer name veth-sab-ns
        ip link set veth-sab-ns netns ${netnsName}
        ip addr add ${hostVethIp}/24 dev veth-sab-host
        ip link set veth-sab-host up
        ip -n ${netnsName} addr add ${nsVethIp}/24 dev veth-sab-ns
        ip -n ${netnsName} link set veth-sab-ns up
        
        # Move Wireguard interface if it exists
        if ip link show ${wgIface} >/dev/null 2>&1; then
          ip link set ${wgIface} netns ${netnsName}
        fi
      '';
      preStop = ''
        export PATH=${pkgs.iproute2}/bin:$PATH
        ip link del veth-sab-host || true
        ip netns del ${netnsName} || true
      '';
    };

    systemd.services.sabnzbd = lib.mkMerge [
      {
        bindsTo = [ "netns-${netnsName}.service" ];
        after = [ "netns-${netnsName}.service" ];
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
          NetworkNamespacePath = "/var/run/netns/${netnsName}";
          MemoryMax = "4G";
          OOMScoreAdjust = 500;
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

    # Proxy via the veth pair into the namespace
    services.caddy.virtualHosts."sabnzbd.${domain}" = {
      extraConfig = ''
        import sso_auth
        reverse_proxy ${nsVethIp}:${toString portSabnzbd}
      '';
    };
  };
}


