# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Stufe 0+ Zugang — Notfall-User, LAN, DNS/IPv6-Assertions
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
#     - docs/adr/002-ipv6-homelab-v4-only.md
#   tags:
#     - access
#     - rollout
# ---
{ config, lib, pkgs, ... }:

let
  p = import ./profile.nix;
  lan = p.network.lan;
  dnsPolicy = import ../../lib/dns-policy.nix { inherit lib; };
  emergency = p.access.emergency;

  lanNetwork = config.systemd.network.networks.${lan.systemdNetworkName} or { };
  lanAddress = lanNetwork.networkConfig.Address or "";
  opensshSettings = config.services.openssh.settings or { };
  firewallPorts = config.networking.firewall.allowedTCPPorts or [ ];
in
{
  users.users.${emergency.name} = {
    isNormalUser = lib.mkForce true;
    description = lib.mkForce emergency.description;
    extraGroups = lib.mkForce emergency.extraGroups;
    # Kein Passwort fuer den Notfall-User -- Wiedereinstieg laeuft ueber
    # physische TTY-Root-Autologin-Konsole + moritz' SSH-Keys, nicht ueber
    # ein zu merkendes Passwort (Entscheidung 2026-06-25).
    hashedPassword = lib.mkForce null;
  };

  my.configs.server.lanIP = lib.mkForce lan.ip;

  # Physische Konsole: root-Autologin auf tty1 -- kein Passwort, keine Huerde,
  # wenn man koerperlich am Geraet sitzt (Entscheidung 2026-06-25).
  services.getty.autologinUser = lib.mkForce "root";

  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;
  systemd.network.enable = lib.mkForce true;
  systemd.network.networks.${lan.systemdNetworkName} = lib.mkForce {
    matchConfig.Name = lan.interface;
    networkConfig = {
      Address = "${lan.ip}/${toString lan.prefixLength}";
      Gateway = lan.gateway;
      DNS = lan.dns;
    } // lib.optionalAttrs (lib.elem lan.interface p.network.ipv6.disableOnInterfaces) {
      IPv6AcceptRA = "no";
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkIf (!config.my.security.firewall.enable) (
    lib.mkForce [ p.network.sshPort ]
  );

  # Git-Repo liegt unter /home/nixos → Deploy-Key für grapefruit89/NixmitGROK
  environment.systemPackages = [ pkgs.git pkgs.openssh ];
  programs.ssh.knownHosts.github = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6fj0Xq7y9eGOs90HzDPW3uTilh/Ar";
  };
  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile /home/nixos/.ssh/id_ed25519_github
      IdentitiesOnly yes
      User git
  '';

  # Headless-Dev / Hardware-Sandbox: wheel ohne Passwort (Grok-Agent, moritz, Notfall-User)
  security.sudo.wheelNeedsPassword = lib.mkForce false;

  assertions = [
    {
      assertion = lib.hasAttr emergency.name config.users.users;
      message = "ACCESS: User '${emergency.name}' muss existieren.";
    }
    {
      assertion = config.users.users.${emergency.name}.isNormalUser or false;
      message = "ACCESS: User '${emergency.name}' muss isNormalUser = true sein.";
    }
    {
      assertion = lib.elem "wheel" (config.users.users.${emergency.name}.extraGroups or [ ]);
      message = "ACCESS: User '${emergency.name}' braucht Gruppe 'wheel' (sudo).";
    }
    {
      assertion = (config.users.users.${emergency.name}.hashedPassword or null) == null;
      message = "ACCESS: '${emergency.name}' darf kein Passwort haben -- Wiedereinstieg nur via TTY-Autologin/SSH-Keys.";
    }
    {
      assertion = config.my.configs.server.lanIP == lan.ip;
      message = "ACCESS: LAN-IP muss ${lan.ip} sein.";
    }
    {
      assertion = !config.networking.useDHCP;
      message = "ACCESS: DHCP muss aus sein (statische IP ${lan.ip}).";
    }
    {
      assertion = lib.hasInfix lan.ip lanAddress;
      message = "ACCESS: systemd.network '${lan.systemdNetworkName}' muss ${lan.ip}/${toString lan.prefixLength} auf ${lan.interface} setzen.";
    }
    {
      assertion = config.services.openssh.enable or false;
      message = "ACCESS: OpenSSH muss aktiviert sein.";
    }
    {
      assertion = lib.elem p.network.sshPort (config.services.openssh.ports or [ ]);
      message = "ACCESS: SSH muss auf Port ${toString p.network.sshPort} lauschen.";
    }
    {
      assertion = !(opensshSettings.PasswordAuthentication or false);
      message = "ACCESS: SSH PasswordAuthentication muss false sein -- nur SSH-Keys (Entscheidung 2026-06-25).";
    }
    {
      assertion =
        !config.my.security.firewall.enable
        || lib.elem p.network.sshPort firewallPorts;
      message = "ACCESS: Firewall aktiv → Port ${toString p.network.sshPort} muss erlaubt sein.";
    }
    {
      assertion =
        !(config.my.services.blocky.enable or false)
        || (
          lan.dns == [ "127.0.0.1" ]
          && dnsPolicy.allEncrypted p.network.blocky.upstream
          && dnsPolicy.allEncrypted p.network.dns.bootstrap
        );
      message = "ACCESS: WAN-DNS nur via Blocky/DoT — LAN-DNS nur 127.0.0.1, keine Klartext-Upstreams in profile.nix.";
    }
  ];
}