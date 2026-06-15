{ config, lib, ... }:

let
  p = import ./profile.nix;
  lan = p.network.lan;
  emergency = p.access.emergency;

  lanNetwork = config.systemd.network.networks.${lan.systemdNetworkName} or { };
  lanAddress = lanNetwork.networkConfig.Address or "";
  opensshSettings = config.services.openssh.settings or { };
  firewallPorts = config.networking.firewall.allowedTCPPorts or [ ];
in
{
  users.users.${emergency.name} = {
    isNormalUser = lib.mkForce true;
    extraGroups = lib.mkForce emergency.extraGroups;
    hashedPassword = lib.mkForce emergency.passwordHash;
  };

  my.configs.server.lanIP = lib.mkForce lan.ip;

  networking.useDHCP = lib.mkForce false;

  systemd.network.enable = lib.mkForce true;
  systemd.network.networks.${lan.systemdNetworkName} = lib.mkForce {
    matchConfig.Name = lan.interface;
    networkConfig = {
      Address = "${lan.ip}/${toString lan.prefixLength}";
      Gateway = lan.gateway;
      DNS = lan.dns;
    };
  };

  assertions = [
    {
      assertion = lib.hasAttr emergency.name config.users.users;
      message = "ZUGANG-SICHERUNG: User '${emergency.name}' muss existieren.";
    }
    {
      assertion = config.users.users.${emergency.name}.isNormalUser or false;
      message = "ZUGANG-SICHERUNG: User '${emergency.name}' muss isNormalUser = true sein.";
    }
    {
      assertion = lib.elem "wheel" (config.users.users.${emergency.name}.extraGroups or [ ]);
      message = "ZUGANG-SICHERUNG: User '${emergency.name}' braucht Gruppe 'wheel' (sudo).";
    }
    {
      assertion =
        (config.users.users.${emergency.name}.hashedPassword or "") == emergency.passwordHash;
      message = "ZUGANG-SICHERUNG: Passwort-Hash für '${emergency.name}' fehlt oder wurde geändert.";
    }
    {
      assertion = config.my.configs.server.lanIP == lan.ip;
      message = "ZUGANG-SICHERUNG: LAN-IP muss ${lan.ip} sein.";
    }
    {
      assertion = !config.networking.useDHCP;
      message = "ZUGANG-SICHERUNG: DHCP muss aus sein (statische IP ${lan.ip}).";
    }
    {
      assertion = lib.hasInfix lan.ip lanAddress;
      message = "ZUGANG-SICHERUNG: systemd.network '${lan.systemdNetworkName}' muss ${lan.ip}/${toString lan.prefixLength} auf ${lan.interface} setzen.";
    }
    {
      assertion = config.services.openssh.enable or false;
      message = "ZUGANG-SICHERUNG: OpenSSH muss aktiviert sein.";
    }
    {
      assertion = lib.elem p.network.sshPort (config.services.openssh.ports or [ ]);
      message = "ZUGANG-SICHERUNG: SSH muss auf Port ${toString p.network.sshPort} lauschen.";
    }
    {
      assertion = opensshSettings.PasswordAuthentication or false;
      message = "ZUGANG-SICHERUNG: SSH PasswordAuthentication muss true sein.";
    }
    {
      assertion =
        !config.my.security.firewall.enable
        || lib.elem p.network.sshPort firewallPorts;
      message = "ZUGANG-SICHERUNG: Firewall aktiv → Port ${toString p.network.sshPort} muss erlaubt sein.";
    }
  ];
}