# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Stufe 0+ Zugang — LAN, DNS/IPv6-Assertions, SSH-Gate
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
#     - docs/adr/002-ipv6-homelab-v4-only.md
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
  adminUser = import ../../users/admin/profile.nix;

  lanNetwork = config.systemd.network.networks.${lan.systemdNetworkName} or { };
  lanAddress = lanNetwork.networkConfig.Address or "";
  opensshSettings = config.services.openssh.settings or { };
  firewallPorts = config.networking.firewall.allowedTCPPorts or [ ];

  nixosEmergency = {
    name = "nixos";
    description = "Notfall-Zugang (SSH-Key-only, wheel)";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
in
{
  users.users.${nixosEmergency.name} = {
    isNormalUser = lib.mkForce true;
    description = lib.mkForce nixosEmergency.description;
    extraGroups = lib.mkForce nixosEmergency.extraGroups;
    hashedPassword = lib.mkForce null;
    # Gleiche SSH-Keys wie admin — Notfall-Login wenn admin-User kaputt
    openssh.authorizedKeys.keys = lib.mkForce adminUser.authorizedKeys;
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
    }
    // lib.optionalAttrs (lib.elem lan.interface p.network.ipv6.disableOnInterfaces) {
      IPv6AcceptRA = "no";
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkIf (!config.my.security.firewall.enable) (
    lib.mkForce [ p.network.sshPort ]
  );

  # Git-Repo /etc/nixos: Deploy-Key liegt unter /root/.ssh/ (nach Migration von /home/nixos)
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

  # Headless-Dev / Hardware-Sandbox: wheel ohne Passwort (Grok-Agent, admin)
  security.sudo.wheelNeedsPassword = lib.mkForce false;

  assertions = [
    {
      assertion = lib.hasAttr nixosEmergency.name config.users.users;
      message = "ACCESS: Notfall-User '${nixosEmergency.name}' muss existieren.";
    }
    {
      assertion = config.users.users.${nixosEmergency.name}.isNormalUser or false;
      message = "ACCESS: Notfall-User '${nixosEmergency.name}' muss isNormalUser = true sein.";
    }
    {
      assertion = lib.elem "wheel" (config.users.users.${nixosEmergency.name}.extraGroups or [ ]);
      message = "ACCESS: Notfall-User '${nixosEmergency.name}' braucht Gruppe 'wheel' (sudo).";
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
      assertion = !config.my.security.firewall.enable || lib.elem p.network.sshPort firewallPorts;
      message = "ACCESS: Firewall aktiv → Port ${toString p.network.sshPort} muss erlaubt sein.";
    }
    {
      assertion =
        !(config.my.services.technitium-dns-server.enable or false) || lan.dns == [ "127.0.0.1" ];
      message = "ACCESS: Technitium aktiv → LAN-DNS muss 127.0.0.1 sein.";
    }
    {
      assertion = (config.services.getty.autologinUser or "") == "root";
      message = "ACCESS: tty1 muss root-Autologin haben — physischer Konsolen-Zugang ist der einzige Notfall-Weg ohne SSH.";
    }
    {
      assertion = !config.security.sudo.wheelNeedsPassword;
      message = "ACCESS: wheel muss passwortlos sudo haben — kein Passwort gesetzt, SSH-Key-Only-Policy erfordert wheelNeedsPassword = false.";
    }
  ]
  ++
    # POLICY: Jeder SSH-User muss wheel haben — niemals ein normaler User ohne sudo
    (
      let
        normalUsers = lib.filterAttrs (
          _n: u: (u.isNormalUser or false) && (u.openssh.authorizedKeys.keys or [ ]) != [ ]
        ) config.users.users;
      in
      lib.mapAttrsToList (name: _u: {
        assertion = lib.elem "wheel" (config.users.users.${name}.extraGroups or [ ]);
        message = "ACCESS: SSH-User '${name}' hat authorized_keys aber KEIN wheel — sudo-loser SSH-User verboten!";
      }) normalUsers
    );
}
