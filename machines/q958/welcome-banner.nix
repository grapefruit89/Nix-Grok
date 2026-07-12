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
in
{
  # TTY vor Login (physische Konsole)
  environment.etc.issue.text = lib.mkForce bannerShort;
  environment.etc."issue.net".text = lib.mkForce bannerShort;

  # Nach Login (SSH + Konsole)
  environment.etc.motd.text = lib.mkForce bannerFull;

  # SSH Pre-auth Banner (sichtbar vor Key-Auth)
  services.openssh.settings.Banner = lib.mkDefault "/etc/ssh/banner";
  environment.etc."ssh/banner".text = lib.mkForce bannerShort;

  # Zusätzlich: interaktive Shell (falls motd übersprungen)
  programs.bash.interactiveShellInit = lib.mkOrder 500 ''
    if [[ -z "''${Q958_WELCOME_SHOWN:-}" && -t 1 ]]; then
      export Q958_WELCOME_SHOWN=1
      cat /etc/motd 2>/dev/null || true
    fi
  '';
}
