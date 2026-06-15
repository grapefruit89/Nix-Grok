# Legacy-Standalone — Werte aus machines/q958/profile.nix + users/moritz/profile.nix
{ config, lib, pkgs, ... }:

let
  p = import ./machines/q958/profile.nix;
  moritz = import ./users/moritz/profile.nix;
  lan = p.network.lan;
  emergency = p.access.emergency;
in
{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = p.system.hostName;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  system.nixos.distroName = p.boot.menuName;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = p.boot.generationLimit;
    sortKey = p.boot.sortKey;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = false;
  networking.networkmanager.enable = true;
  systemd.network.enable = true;
  systemd.network.networks.${lan.systemdNetworkName} = {
    matchConfig.Name = lan.interface;
    networkConfig = {
      Address = "${lan.ip}/${toString lan.prefixLength}";
      Gateway = lan.gateway;
      DNS = lan.dns;
    };
  };

  users.users.${emergency.name} = {
    isNormalUser = true;
    description = emergency.description;
    extraGroups = emergency.extraGroups;
    hashedPassword = emergency.passwordHash;
  };

  users.users.${moritz.name} = {
    isNormalUser = true;
    description = moritz.description;
    extraGroups = moritz.extraGroups;
    openssh.authorizedKeys.keys = moritz.authorizedKeys;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [ p.network.sshPort ];

  environment.systemPackages = with pkgs; [
    vim wget curl git htop pciutils usbutils smartmontools
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = p.system.stateVersion;
}