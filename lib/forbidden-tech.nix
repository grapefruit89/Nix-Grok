{ lib }:
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
    semaphore = "Semaphore/Ansible verboten — imperatives Infrastruktur-Management widerspricht dem deklarativen NixOS-Mindset. NixOS ist die einzige Wahrheitsquelle (ADR-034).";
    cockpit = "Cockpit entfernt — Angriffsfläche überwiegt Nutzen für Ein-Personen-Homelab (ADR-033). SSH + nixos-rebuild ist die einzige Admin-Schnittstelle.";
    n8n = "n8n verboten — Workflow-Automatisierung gehört in NixOS-Module + systemd-Services, nicht in einen Workflow-Engine-Daemon (ADR-034).";
    forgejo = "Forgejo/Gitea verboten — kein Self-Hosted Git auf q958. GitHub ist ausreichend; Self-Hosted Git erhöht Attack Surface ohne Nutzen (ADR-034).";

    # Formatter-Policy
    fmtBanned = "Verbotener Nix-Formatter — ausschließlich nixfmt (RFC-Style) + statix + deadnix.";
    fmtMissing = "Pflicht-Formatter fehlt in systemPackages — nixfmt + statix + deadnix müssen installiert sein.";

    # Caddy-Plugin-Policy (ADR-7005, ADR-1031) — Caddy ist Ingress only
    caddyPlugins = "Caddy-Plugins verboten — stattdessen: Ingress-only Caddy (reverse_proxy + forward_auth). Kein services.caddy.package mit withPlugins.";
    caddyRatelimit = "caddy-ratelimit verboten — stattdessen: nftables webRateLimit in lib/nftables-rules.nix (L4, ~100/min pro WAN-IP auf 80/443).";
    caddyTransformEncoder = "transform-encoder (Apache-Logs) verboten — stattdessen: JSON-Logs + journald (services.caddy.logFormat, ADR-1018).";
    caddyWol = "caddy-wol verboten — stattdessen: separates WOL-Tooling am NAS/PC (ethtool/wakeonlan), nicht im Ingress.";
    caddyDnsCloudflare = "caddy-dns/cloudflare verboten — stattdessen: security.acme + lego DNS-01 (modules/20-security/2023-acme.nix).";
    caddyInternalAcme = "Caddy-internes ACME verboten — stattdessen: security.acme + useACMEHost (Zertifikate aus /var/lib/acme/).";
    sablier = "Sablier verboten — widerspricht No-Docker-Policy; stattdessen: systemd socket activation oder always-on Services.";
  };

  hasPkg =
    config: name: builtins.any (p: (p.pname or p.name or "") == name) config.environment.systemPackages;

  hasInfix = needle: haystack: lib.strings.hasInfix needle haystack;

  caddyCfgText =
    config:
    let
      cfg = config.services.caddy or { };
    in
    (cfg.extraConfig or "") + (cfg.globalConfig or "");

  caddyEnabled = config: config.services.caddy.enable or false;
in
{
  inherit must reasons;

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
    (must (!(config.services.semaphore.enable or false)) "[POL-FT-009] Semaphore: ${reasons.semaphore}")
    (must (!(config.services.cockpit.enable or false)) "[POL-FT-010] Cockpit: ${reasons.cockpit}")
    (must (!(config.services.n8n.enable or false)) "[POL-FT-011] n8n: ${reasons.n8n}")
    (must (!(config.services.forgejo.enable or false)) "[POL-FT-012] Forgejo: ${reasons.forgejo}")
    (must (!(config.services.gitea.enable or false)) "[POL-FT-012] Gitea: ${reasons.forgejo}")
  ];

  firewallAssertions = config: [
    (must (
      config.networking.nftables.enable == true
    ) "[POL-FT-005] nftables Pflicht: ${reasons.iptables}")
  ];

  formatterAssertions = config: [
    (must (hasPkg config "nixfmt") "[POL-FMT-010] nixfmt fehlt: ${reasons.fmtMissing}")
    (must (hasPkg config "statix") "[POL-FMT-011] statix fehlt: ${reasons.fmtMissing}")
    (must (hasPkg config "deadnix") "[POL-FMT-012] deadnix fehlt: ${reasons.fmtMissing}")
    (must (!(hasPkg config "alejandra")) "[POL-FMT-001] alejandra: ${reasons.fmtBanned}")
    (must (!(hasPkg config "nixpkgs-fmt")) "[POL-FMT-002] nixpkgs-fmt: ${reasons.fmtBanned}")
    (must (!(hasPkg config "rnix-linter")) "[POL-FMT-003] rnix-linter: ${reasons.fmtBanned}")
  ];

  # Caddy: keine Plugins / keine doppelte Infrastruktur (DDNS, ACME, Rate-Limit, WOL, Sablier)
  caddyAssertions =
    config: pkgs:
    let
      cfg = config.services.caddy or { };
      enabled = caddyEnabled config;
      caddyText = caddyCfgText config;
      stockCaddy = cfg.package or pkgs.caddy;
      forbiddenInCaddyfile =
        patterns: enabled && builtins.any (pattern: hasInfix pattern caddyText) patterns;
    in
    [
      (must (
        !enabled || stockCaddy == pkgs.caddy
      ) "[POL-CADDY-001] Caddy-Plugins: ${reasons.caddyPlugins}")
      (must (
        !enabled || !(config.my.security.acme.enable or false) || (cfg.acmeCA or null) == null
      ) "[POL-CADDY-002] Caddy-ACME: ${reasons.caddyInternalAcme}")
      (must (
        !forbiddenInCaddyfile [
          "rate_limit"
          "caddy-ratelimit"
          "http.ratelimit"
        ]
      ) "[POL-CADDY-003] caddy-ratelimit: ${reasons.caddyRatelimit}")
      (must (
        !forbiddenInCaddyfile [
          "transform-encoder"
          "encode apache"
          "transform encode"
        ]
      ) "[POL-CADDY-004] transform-encoder: ${reasons.caddyTransformEncoder}")
      (must (
        !forbiddenInCaddyfile [
          "caddy-wol"
          "wake_on_lan"
          "wake-on-lan"
        ]
      ) "[POL-CADDY-005] caddy-wol: ${reasons.caddyWol}")
      (must (
        !forbiddenInCaddyfile [
          "caddy-dns/cloudflare"
          "acme_dns cloudflare"
          "dns.cloudflare"
        ]
      ) "[POL-CADDY-006] caddy-dns/cloudflare: ${reasons.caddyDnsCloudflare}")
      (must (
        !(config.services.sablier.enable or false)
        && !forbiddenInCaddyfile [
          "sablier"
          "github.com/sablier"
        ]
      ) "[POL-CADDY-007] Sablier: ${reasons.sablier}")
    ];
}
