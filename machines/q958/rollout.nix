# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Einzige Quelle für .enable — schrittweise Aktivierung nach rollout.stufe
#   docs:
#     - docs/ROADMAP.md
#   lib:
#     - lib/rollout.nix
#   tags:
#     - rollout
#     - enable
# ---
{ lib, ... }:
let
  p = import ./profile.nix;
  stufe = p.rollout.stufe;
  rollout = import ../../lib/rollout.nix { inherit lib stufe; };
  inherit (rollout) erstAb;
in
{
  system.nixos.distroName =
    if stufe >= 9 then lib.mkForce "Production (Impermanence)" else lib.mkForce p.boot.menuName;
  boot.loader.systemd-boot.configurationLimit = lib.mkForce p.boot.generationLimit;
  boot.loader.systemd-boot.sortKey =
    if stufe >= 9 then lib.mkForce "9_production" else lib.mkForce p.boot.sortKey;
  system.stateVersion = lib.mkForce p.system.stateVersion;

  my.mode = if stufe >= 9 then lib.mkForce "production" else lib.mkForce "development";

  my.core = {
    boot-safeguard.enable = erstAb 1;
    kernel-slim.enable = erstAb 1;
    nix-tuning.enable = erstAb 1;
    zram-swap.enable = erstAb 1;
  };

  my.security = {
    sovereign-unlock.enable = if p.storage.luks.device == "" then lib.mkForce false else erstAb 8;
    firewall = {
      enable = erstAb 8;
      skuidSegmentation.enable = erstAb 8;
    };
    crowdsec.enable = erstAb 8;
    fail2ban.enable = erstAb 8;
    dropbear-rescue.enable = erstAb 8;
    kernel-hardening.enable = erstAb 8;
    hardened.enable = erstAb 9;
  };

  my.storage.deferred.enable = erstAb 3;

  my.alerting.enable = erstAb 8;

  my.observability.enable = erstAb 4;
  my.observability.victoriametrics.enable = erstAb 7;
  my.impermanence.enable = erstAb 9;

  my.services = {
    technitium-dns-server.enable = erstAb 2;
    valkey.enable = erstAb 2;
    postgresql.enable = lib.mkForce false;
    netbird.enable = erstAb 2;
    pocket-id.enable = erstAb 2; # /var/lib/secrets/pocket-id.env (secrets-provision)
    privado-vpn.enable = erstAb 6; # Usenet: SABnzbd + Prowlarr — Key in profile.local.nix

    storage.enable = if p.storage.mergerfsEnable then erstAb 3 else lib.mkForce false;
    storage-automount.enable = erstAb 3;

    gatus.enable = erstAb 4;
    restic-backup.enable = if p.restic.offsiteEnable then erstAb 6 else lib.mkForce false;

    jellyfin.enable = erstAb 6;
    jellyseerr.enable = erstAb 6;
    audiobookshelf.enable = erstAb 6;
    navidrome.enable = erstAb 6;
    sonarr.enable = erstAb 6;
    radarr.enable = erstAb 6;
    readarr.enable = erstAb 6;
    prowlarr.enable = erstAb 6;
    sabnzbd.enable = erstAb 6;
    lidarr.enable = erstAb 6;

    vaultwarden.enable = erstAb 7;
    homepage.enable = erstAb 7;
    paperless.enable = erstAb 7;
    filebrowser.enable = erstAb 7;
    linkwarden.enable = erstAb 7;
    open-webui.enable = erstAb 7;
    hermes.enable = erstAb 7;
    hermes.containerMode = false; # nativ statt Podman (Entscheidung 2026-06-26)
    home-assistant.enable = erstAb 7;
    zigbee-stack.enable = erstAb 7;
    amp.enable = erstAb 7;
  };

  services.hermes-agent.enable = erstAb 7;
  services.caddy.enable = erstAb 5;
  my.ingress.fromSpec.enable = erstAb 5;

  my.security.runtime-guard.enable = erstAb 8;
  my.boot-watchdog.enable = erstAb 5;
  my.disk-health.enable = erstAb 3;

  my.services.vpn-confinement = {
    enable = erstAb 6;
    leakCheck.enable = erstAb 6;
  };

  my.ports.ssh =
    if stufe >= 9 then lib.mkForce p.network.productionSshPort else lib.mkForce p.network.sshPort;

  my.sops.enable = erstAb 9;

  my.services.ddns-updater.enable = if p.network.ddns.enable then erstAb 5 else lib.mkForce false;
  my.services.dns-guard.enable = if p.network.ddns.enable then erstAb 5 else lib.mkForce false;

  networking.firewall.allowedTCPPorts = lib.mkIf (stufe < 8) (lib.mkForce [ p.network.sshPort ]);

  assertions = [
    {
      assertion = !(stufe >= 9 && p.storage.impermanence.mountPoint == "/");
      message = "Stufe 9: storage.impermanence.mountPoint muss != \"/\" sein (z. B. /persist).";
    }
  ];
}
