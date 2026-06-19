# Schrittweise Aktivierung — eine Zahl in profile.nix: rollout.stufe
#
#   0 = Zugang + Grok CLI (SSH, statische IP, Headless-Dev) — Homelab-Dienste aus
#   1 = System-Tuning (zram, kernel-slim, boot-safeguard, nix-tuning)
#   2 = Netzwerk-Basis (postgresql, valkey, blocky, tailscale, pocket-id, privado)
#       Secrets: Dateien unter /var/lib/secrets (siehe secrets.nix) — AdGuard aus (Port 53)
#   3 = Storage (automount + mergerfs wenn storage.mergerfsEnable)
#   4 = Observability (gatus, metrics)
#   5 = Reverse Proxy (caddy)
#   6 = Media-Stack (*arr, jellyfin, sabnzbd, restic)
#   7 = Apps (vaultwarden, homepage, paperless, HA, hermes, …)
#   8 = Security (firewall, fail2ban, crowdsec, dropbear)
#   9 = Impermanence (production mode)
#  SOPS = ganz zum Schluss, separat
{ config, lib, ... }:

let
  p = import ./profile.nix;
  stufe = p.rollout.stufe;
  rollout = import ../../lib/rollout.nix { inherit lib stufe; };
  inherit (rollout) erstAb;
in
{
  system.nixos.distroName = lib.mkIf (stufe < 9) (lib.mkForce p.boot.menuName);
  boot.loader.systemd-boot.configurationLimit = lib.mkForce p.boot.generationLimit;
  boot.loader.systemd-boot.sortKey = lib.mkIf (stufe < 9) (lib.mkForce p.boot.sortKey);
  system.stateVersion = lib.mkForce p.system.stateVersion;

  my.mode =
    if stufe >= 9 then lib.mkForce "production"
    else lib.mkForce "development";

  my.core = {
    boot-safeguard.enable = erstAb 1;
    kernel-slim.enable = erstAb 1;
    nix-tuning.enable = erstAb 1;
    zram-swap.enable = erstAb 1;
  };

  my.security = {
    sovereign-unlock.enable =
      if p.storage.luks.device == "" then lib.mkForce false else erstAb 8;
    firewall.enable = erstAb 8;
    crowdsec.enable = erstAb 8;
    fail2ban.enable = erstAb 8;
    dropbear-rescue.enable = erstAb 8;
  };

  my.observability.enable = erstAb 4;
  my.impermanence.enable = erstAb 9;

  my.services = {
    # Blocky ist unser DNS (Port-53-Konflikt)
    valkey.enable = erstAb 2;

    blocky.enable = erstAb 2;
    tailscale.enable = erstAb 2;
    pocket-id.enable = erstAb 2; # /var/lib/secrets/pocket-id.env (secrets-provision)
    privado-vpn.enable = lib.mkForce false; # privado_private_key manuell vom Provider

    storage.enable =
      if p.storage.mergerfsEnable then erstAb 3 else lib.mkForce false;
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
    grok.enable = lib.mkForce true; # Headless-Dev — immer an, unabhängig von rollout.stufe
  };

  services.hermes-agent.enable = erstAb 7;
  services.caddy.enable = erstAb 5;

  networking.firewall.allowedTCPPorts = lib.mkIf (stufe < 8) (
    lib.mkForce [ p.network.sshPort ]
  );
}

