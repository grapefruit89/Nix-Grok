/*
  ---
  id: sabnzbd
  upstream_repo: "sabnzbd/sabnzbd"
  ---
*/

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfgSabnzbd = config.my.services.sabnzbd;
  domain = config.my.configs.identity.domain;
  portSabnzbd = config.my.ports.sabnzbd;

  netnsName = "sabnzbd-vpn";
  wgIface = "privado";
  hostVethIp = "10.100.100.1";
  nsVethIp = "10.100.100.2";

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

          if [ -f /data/state/sabnzbd/sabnzbd.ini ]; then
            # RAM-Disk Setup (Incomplete Downloads)
            ${pkgs.gnused}/bin/sed -i 's/^download_dir\s*=.*/download_dir = \/run\/sabnzbd-tmp/g' /data/state/sabnzbd/sabnzbd.ini

            # Remove existing [servers] and everything below it until the next section
            ${pkgs.gnused}/bin/sed -i '/^\[servers\]/,/^\[/{/^\[servers\]/d;/^\[/!d}' /data/state/sabnzbd/sabnzbd.ini
            
            # Inject declarative servers block
            PASSWORD_NEWS=$(cat "''${CREDENTIALS_DIRECTORY}/SABNZBD_PASSWORD_NEWS")
            PASSWORD_EASY=$(cat "''${CREDENTIALS_DIRECTORY}/SABNZBD_PASSWORD_EASY")
            cat <<EOF >> /data/state/sabnzbd/sabnzbd.ini
[servers]
[[news.newshosting.com]]
name = news.newshosting.com
displayname = news.newshosting.com
host = news.newshosting.com
port = 563
timeout = 60
username = p8embyavo
password = $PASSWORD_NEWS
connections = 100
ssl = 1
ssl_verify = 2
ssl_ciphers = ""
enable = 1
priority = 0

[[news.easynews.com]]
name = news.easynews.com
displayname = news.easynews.com
host = news.easynews.com
port = 563
timeout = 60
username = p8embyavo@newshosting.com
password = $PASSWORD_EASY
connections = 8
ssl = 1
ssl_verify = 3
ssl_ciphers = ""
enable = 1
priority = 5

[[newshosting.tweaknews.eu]]
name = newshosting.tweaknews.eu
displayname = newshosting.tweaknews.eu
host = newshosting.tweaknews.eu
port = 563
timeout = 60
username = fveuyzfdavra
password = $PASSWORD_NEWS
connections = 40
ssl = 1
ssl_verify = 3
ssl_ciphers = ""
enable = 1
priority = 4
EOF
          fi
        '';
        serviceConfig = {
          LoadCredential = [
            "SABNZBD_PASSWORD_NEWS:/home/moritz/secrets/sabnzbd_password"
            "SABNZBD_PASSWORD_EASY:/home/moritz/secrets/sabnzbd_password_easynews"
          ];
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
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 4;
          LimitNOFILE = 65536;
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
