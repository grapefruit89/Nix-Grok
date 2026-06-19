{ config, lib, ... }:

let
  p = import ./profile.nix;
  lan = p.network.lan;
  emergency = p.access.emergency;
  einfuehrungsStufe = p.rollout.stufe;

  erstAb = stufe: lib.mkIf (einfuehrungsStufe < stufe) (lib.mkForce false);
in
{
  users.users.${emergency.name} = {
    isNormalUser = true;
    description = emergency.description;
    extraGroups = emergency.extraGroups;
    hashedPassword = emergency.passwordHash;
  };

  system.nixos.distroName = lib.mkIf (einfuehrungsStufe < 9) (lib.mkForce p.boot.menuName);
  boot.loader.systemd-boot.configurationLimit = lib.mkForce p.boot.generationLimit;
  boot.loader.systemd-boot.sortKey = lib.mkIf (einfuehrungsStufe < 9) (lib.mkForce p.boot.sortKey);
  system.stateVersion = lib.mkForce p.system.stateVersion;

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

  my.mode = lib.mkIf (einfuehrungsStufe < 9) (lib.mkForce "development");

  my.core = {
    boot-safeguard.enable = erstAb 1;
    kernel-slim.enable = erstAb 1;
    nix-tuning.enable = lib.mkForce true;
    zram-swap.enable = erstAb 1;
  };

  my.security = {
    sovereign-unlock.enable = erstAb 8;
    firewall.enable = erstAb 8;
    crowdsec.enable = erstAb 8;
    fail2ban.enable = erstAb 8;
    dropbear-rescue.enable = erstAb 8;
  };

  my.observability.enable = erstAb 4;
  my.impermanence.enable = erstAb 9;

  my.services = {

    valkey.enable = erstAb 2;

    blocky.enable = erstAb 2;
    tailscale.enable = erstAb 2;
    pocket-id.enable = erstAb 2;

    storage.enable = erstAb 3;
    storage-automount.enable = erstAb 3;

    gatus.enable = erstAb 4;
    restic-backup.enable = erstAb 6;

    jellyfin.enable = erstAb 6;
    jellyseerr.enable = erstAb 6;
    sonarr.enable = erstAb 6;
    radarr.enable = erstAb 6;
    readarr.enable = erstAb 6;
    prowlarr.enable = erstAb 6;
    sabnzbd.enable = erstAb 6;

    vaultwarden.enable = erstAb 7;
    homepage.enable = erstAb 7;
    paperless.enable = erstAb 7;
    n8n.enable = erstAb 7;
    filebrowser.enable = erstAb 7;
    linkwarden.enable = erstAb 7;
    open-webui.enable = erstAb 7;
    hermes.enable = erstAb 7;
    home-assistant.enable = erstAb 7;
    zigbee-stack.enable = erstAb 7;
    semaphore.enable = erstAb 7;
    amp.enable = erstAb 7;

    grok.enable = lib.mkForce true;
  };

  services.hermes-agent.enable = erstAb 7;
  services.caddy.enable = erstAb 5;

  networking.firewall.allowedTCPPorts = lib.mkIf (einfuehrungsStufe < 8) (
    lib.mkForce [ p.network.sshPort ]
  );
}

