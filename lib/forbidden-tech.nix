# ---
# meta:
#   id: NIXH-05-LIB-008
#   layer: 5
#   role: lib
#   purpose: Forbidden-technology Assertions (subset mynixos-v5, ohne Tailscale-Ban)
#   tags:
#     - policy
#     - security
# ---
{ ... }:

let
  must = assertion: message: { inherit assertion message; };

  reasons = {
    docker = "Docker widerspricht NixOS-native systemd — mkService nutzen.";
    cron = "cron ist veraltet — systemd-Timer verwenden.";
    iptables = "iptables legacy — ausschließlich nftables.";
    sftpgo = "SFTPGo verboten — Filebrowser oder OpenSSH.";
    lanzaboote = "Lanzaboote nicht im Einsatz — systemd-boot.";
    passwords = "SSH-Passwort-Auth nur in Dev (Stufe < 9) — Production key-only.";
  };
in
{
  inherit must reasons;

  # Immer aktiv (unabhängig von Firewall/Mode)
  baselineAssertions = config: [
    (must (!(config.virtualisation.docker.enable or false)) "[POL-FT-001] Docker: ${reasons.docker}")
    (must (!(config.services.cron.enable or false)) "[POL-FT-002] Cron: ${reasons.cron}")
    (must (!(config.services.sftpgo.enable or false)) "[POL-FT-003] SFTPGo: ${reasons.sftpgo}")
    (must (!(config.boot.lanzaboote.enable or false)) "[POL-FT-004] Lanzaboote: ${reasons.lanzaboote}")
  ];

  # Wenn nftables-Firewall-Stack aktiv
  firewallAssertions = config: [
    (must (
      config.networking.nftables.enable == true
    ) "[POL-FT-005] nftables Pflicht: ${reasons.iptables}")
  ];
}
