# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Stufe 0+ Zugang — LAN, DNS/IPv6, root-tty + jarvis-SSH
#   docs:
#     - docs/adr/1001-dns-dot-fail-closed.md
#     - docs/adr/1002-ipv6-homelab-v4-only.md
#   tags:
#     - access
#     - rollout
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  p = import ./profile.nix;
  lan = p.network.lan;

  lanNetwork = config.systemd.network.networks.${lan.systemdNetworkName} or { };
  lanAddress = lanNetwork.networkConfig.Address or "";
  firewallPorts = config.networking.firewall.allowedTCPPorts or [ ];
  identityUser = config.my.configs.identity.user;
in
{
  my.configs.server.lanIP = lib.mkForce lan.ip;

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
    }
    // lib.optionalAttrs (lib.elem lan.interface p.network.ipv6.disableOnInterfaces) {
      IPv6AcceptRA = "no";
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkIf (!config.my.security.firewall.enable) (
    lib.mkForce [ p.network.sshPort ]
  );

  environment.systemPackages = [
    pkgs.git
    pkgs.openssh
  ];
  programs.ssh.knownHosts.github = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6fj0Xq7y9eGOs90HzDPW3uTilh/Ar";
  };
  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile /root/.ssh/id_ed25519_github
      IdentitiesOnly yes
      User git
  '';

  security.sudo.wheelNeedsPassword = lib.mkForce false;

  assertions = [
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
      assertion = !config.my.security.firewall.enable || lib.elem p.network.sshPort firewallPorts;
      message = "ACCESS: Firewall aktiv → Port ${toString p.network.sshPort} muss erlaubt sein.";
    }
    {
      assertion = !(config.my.services.blocky.enable or false) || lan.dns == [ "127.0.0.1" ];
      message = "ACCESS: Blocky aktiv → LAN-DNS muss 127.0.0.1 sein.";
    }
  ]
  ++ (
    let
      normalUsers = lib.filterAttrs (
        _n: u: (u.isNormalUser or false) && (u.openssh.authorizedKeys.keys or [ ]) != [ ]
      ) config.users.users;
    in
    lib.mapAttrsToList (name: _u: {
      assertion = lib.elem "wheel" (config.users.users.${name}.extraGroups or [ ]);
      message = "ACCESS: SSH-User '${name}' hat authorized_keys aber KEIN wheel — sudo-loser SSH-User verboten!";
    }) normalUsers
  )
  ++ [
    {
      assertion = lib.elem "wheel" (config.users.users.${identityUser}.extraGroups or [ ]);
      message = "ACCESS: identity.user '${identityUser}' muss in Gruppe wheel sein.";
    }
  ];
}
