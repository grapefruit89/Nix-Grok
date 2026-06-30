_:
let
  must = assertion: message: { inherit assertion message; };

  reasons = {
    docker = "Docker widerspricht NixOS-native systemd — mkService nutzen.";
    cron = "cron ist veraltet — systemd-Timer verwenden.";
    iptables = "iptables legacy — ausschließlich nftables.";
    sftpgo = "SFTPGo verboten — Filebrowser oder OpenSSH.";
    lanzaboote = "Lanzaboote nicht im Einsatz — systemd-boot.";
    passwords = "SSH-Passwort-Auth nur in Dev (Stufe < 9) — Production key-only.";
    gui = "X11/Wayland verboten auf Headless-Server — Desktop-Pakete fressen RAM + vergrößern Attack Surface (ADR-020).";

    # Formatter-Policy
    fmtBanned = "Verbotener Nix-Formatter — ausschließlich nixfmt (RFC-Style) + statix + deadnix.";
    fmtMissing = "Pflicht-Formatter fehlt in systemPackages — nixfmt + statix + deadnix müssen installiert sein.";
  };

  # Hilfsfunktion: prüft ob ein Paket (über pname/name) in systemPackages ist
  hasPkg =
    config: name: builtins.any (p: (p.pname or p.name or "") == name) config.environment.systemPackages;
in
{
  inherit must reasons;

  # Immer aktiv (unabhängig von Firewall/Mode)
  baselineAssertions = config: [
    (must (!(config.virtualisation.docker.enable or false)) "[POL-FT-001] Docker: ${reasons.docker}")
    (must (!(config.services.cron.enable or false)) "[POL-FT-002] Cron: ${reasons.cron}")
    (must (!(config.services.sftpgo.enable or false)) "[POL-FT-003] SFTPGo: ${reasons.sftpgo}")
    (must (!(config.boot.lanzaboote.enable or false)) "[POL-FT-004] Lanzaboote: ${reasons.lanzaboote}")
    (must (!(config.services.xserver.enable or false)) "[POL-FT-006] X11: ${reasons.gui}")
    (must (
      !(config.services.desktopManager.gnome.enable or false)
    ) "[POL-FT-007] GNOME: ${reasons.gui}")
    (must (
      !(config.services.desktopManager.plasma6.enable or false)
    ) "[POL-FT-008] KDE Plasma: ${reasons.gui}")
  ];

  # Wenn nftables-Firewall-Stack aktiv
  firewallAssertions = config: [
    (must (
      config.networking.nftables.enable == true
    ) "[POL-FT-005] nftables Pflicht: ${reasons.iptables}")
  ];

  # Formatter-Policy: Whitelist (Pflicht) + Blacklist (verboten)
  # Verhindert, dass ein KI-Agent einen anderen Formatter einschleust.
  formatterAssertions = config: [
    # ── Pflicht-Trio ──────────────────────────────────────────────────────────
    (must (hasPkg config "nixfmt") "[POL-FMT-010] nixfmt fehlt: ${reasons.fmtMissing}")
    (must (hasPkg config "statix") "[POL-FMT-011] statix fehlt: ${reasons.fmtMissing}")
    (must (hasPkg config "deadnix") "[POL-FMT-012] deadnix fehlt: ${reasons.fmtMissing}")

    # ── Blacklist: andere Nix-Formatter ───────────────────────────────────────
    (must (!(hasPkg config "alejandra")) "[POL-FMT-001] alejandra: ${reasons.fmtBanned}")
    (must (!(hasPkg config "nixpkgs-fmt")) "[POL-FMT-002] nixpkgs-fmt: ${reasons.fmtBanned}")
    (must (!(hasPkg config "rnix-linter")) "[POL-FMT-003] rnix-linter: ${reasons.fmtBanned}")
  ];
}
