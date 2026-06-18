# Stufe 0+: Zugang — Netzwerk, Notfall-User. Keine blockierenden Assertions.
{ config, lib, ... }:

let
  p = import ./profile.nix;
  lan = p.network.lan;
  emergency = p.access.emergency;
in
{
  security.sudo.extraRules = [
    {
      users = [ emergency.name ];
      commands = [
        { command = "ALL"; options = [ "SETENV" "NOPASSWD" ]; }
      ];
    }
  ];

  users.users.${emergency.name} = {
    isNormalUser = lib.mkForce true;
    description = lib.mkForce emergency.description;
    extraGroups = lib.mkForce emergency.extraGroups;
    hashedPassword = lib.mkForce emergency.passwordHash;
  };

  my.configs.server.lanIP = lib.mkForce lan.ip;
  networking.networkmanager.enable = lib.mkForce false;
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

  networking.firewall.allowedTCPPorts = lib.mkIf (!config.my.security.firewall.enable) (
    lib.mkForce [ p.network.sshPort ]
  );
}