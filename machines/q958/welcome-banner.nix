# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Prominente Begrüßung — secrets-portal, Setup-Hinweise (SSH + TTY)
#   tags:
#     - motd
#     - welcome
#     - secrets
# ---
{
  lib,
  pkgs,
  ...
}:
let
  p = import ./profile.nix;
  domain = p.domain.effective;
  secretsUrl = "https://secrets.${domain}";
  guideUrl = "docs/guides/GUIDE-secrets-portal.md";

  bannerShort = ''
    ╔══════════════════════════════════════════════════════════════════╗
    ║  q958 — EXTERNE SECRETS JETZT SETZEN                              ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  Portal (LAN):  ${secretsUrl}
    ║  Cloudflare · Usenet · VPN · Treasure Maps · Restic              ║
    ║  Danach: sudo nixos-rebuild-safe.sh switch                        ║
    ║  Doku: /etc/nixos/${guideUrl}                                     ║
    ╚══════════════════════════════════════════════════════════════════╝
  '';

  bannerFull = bannerShort + ''

    Nächste Schritte (nichts auswendig lernen — steht bei jedem Login):
      1. Browser im LAN → ${secretsUrl}
      2. Externe Keys eintragen (Portal zeigt nur leer/gesetzt, nie Werte)
      3. sudo nixos-rebuild-safe.sh switch  (Mensch)

    Interne *arr-Keys: automatisch — kein manueller Schritt.
    Notfall-Recovery: /etc/nixos/docs/EMERGENCY-RECOVERY.md
    Kaltstart:        /etc/nixos/docs/guides/GUIDE-cold-start.md
  '';

  showMotdSnippet = ''
    if [[ -z "''${Q958_WELCOME_SHOWN:-}" && -t 1 ]]; then
      export Q958_WELCOME_SHOWN=1
      cat /etc/motd 2>/dev/null || true
    fi
  '';
in
{
  # MOTD-Datei (Quelle für SSH, Login-Shell, TTY-Service)
  environment.etc.motd.text = lib.mkForce bannerFull;

  # SSH: Pre-auth + nach Login
  environment.etc."issue.net".text = lib.mkForce bannerShort;
  services.openssh.settings.Banner = lib.mkDefault "/etc/ssh/banner";
  environment.etc."ssh/banner".text = lib.mkForce bannerShort;

  # Physische Konsole: root-Autologin auf tty1 (access.nix) — kein Login-Prompt,
  # daher /etc/issue wirkungslos. Stattdessen Login-Shell + einmaliger Boot-Print.
  programs.bash.loginShellInit = lib.mkOrder 500 showMotdSnippet;
  programs.bash.interactiveShellInit = lib.mkOrder 500 showMotdSnippet;

  systemd.services.q958-welcome-tty = {
    description = "Prominenter Setup-Hinweis auf physischer Konsole (tty1)";
    wantedBy = [ "multi-user.target" ];
    after = [ "getty@tty1.service" ];
    requires = [ "getty@tty1.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sh -c '${pkgs.coreutils}/bin/cat /etc/motd > /dev/tty1'";
      RemainAfterExit = true;
    };
  };
}
