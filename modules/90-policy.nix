{ config, lib, ... }:

{
  # ============================================================================
  # ZERO-TOLERANCE POLICY & FORBIDDEN TECHNOLOGY
  # ============================================================================
  config = lib.mkIf (config.my.mode == "production" || config.my.mode == "development") {

    # --- HARTE DEAKTIVIERUNGEN ---
    # Diese Dienste werden systemweit erzwungen deaktiviert.
    services.xserver.enable = lib.mkForce false;
    networking.networkmanager.enable = lib.mkForce false;

    # IPv6 Bann (Homelab Area)
    networking.enableIPv6 = lib.mkForce false;

    # Aus v5: Unnötige Desktop- und Peripherie-Daemons abschalten
    services.accounts-daemon.enable = lib.mkForce false;
    services.upower.enable = lib.mkForce false;
    services.printing.enable = lib.mkForce false; # cups
    hardware.bluetooth.enable = lib.mkForce false;
    networking.wireless.enable = lib.mkForce false; # wpa_supplicant

    # --- COMPILER ASSERTIONS (DER TÜRSTEHER) ---
    assertions = [
      {
        assertion = !config.networking.networkmanager.enable;
        message = "KRITISCHER FEHLER [POLICY]: NetworkManager ist verboten. Nutze systemd-networkd.";
      }
      {
        assertion = config.systemd.network.enable;
        message = "KRITISCHER FEHLER [POLICY]: systemd-networkd MUSS aktiv sein, damit die Netzwerkkarte nicht ausfällt.";
      }
      {
        assertion = config.networking.nftables.enable;
        message = "KRITISCHER FEHLER [POLICY]: Native nftables muss zwingend aktiviert sein.";
      }
      {
        assertion = !config.networking.firewall.enable;
        message = "KRITISCHER FEHLER [POLICY]: Legacy iptables-Firewall ist verboten. Nutze 15-firewall.nix (nftables).";
      }
      {
        assertion = !(config.virtualisation.docker.enable or false);
        message = "KRITISCHER FEHLER [POLICY]: Docker ist verboten. Wir nutzen NixOS, Container sind hier unerwünscht.";
      }
      {
        assertion = !(config.virtualisation.podman.enable or false);
        message = "KRITISCHER FEHLER [POLICY]: Podman ist verboten. Keine OCI-Container auf diesem Server.";
      }
      {
        assertion = !(config ? deployment);
        message = "KRITISCHER FEHLER [POLICY]: Colmena Hive Deployment ist verboten. Zu viel Overengineering für dieses System.";
      }
      {
        assertion = !(config.services.transmission.enable or false);
        message = "KRITISCHER FEHLER [POLICY]: Transmission ist verboten. Sabnzbd-only Server!";
      }
      {
        assertion = !config.services.xserver.enable;
        message = "KRITISCHER FEHLER [POLICY]: X11/Wayland ist verboten. Der Server ist headless (TTY-Monitor weiterhin möglich).";
      }
      {
        assertion = !config.networking.enableIPv6;
        message = "KRITISCHER FEHLER [POLICY]: IPv6 ist systemweit verboten (Homelab-Policy).";
      }
      {
        assertion = builtins.all (ns: ns == "127.0.0.1" || ns == "::1") config.networking.nameservers;
        message = "KRITISCHER FEHLER [POLICY]: Unverschlüsseltes IPv4/IPv6 DNS (wie 1.1.1.1) in networking.nameservers ist verboten! Erlaubt ist nur 127.0.0.1 (z.B. für Blocky als lokalen DoT/DoH Resolver).";
      }
      {
        assertion = config.nixpkgs.overlays == [ ];
        message = "KRITISCHER FEHLER [POLICY]: Globale nixpkgs.overlays sind verboten. Nutze lokale Package-Inputs zur Vermeidung von Supply-Chain-Risiken und Rebuild-Stürmen.";
      }
    ]
    ++ (
      let
        bannedPackages = [
          "nix-linter"
          "nixpkgs-lint"
          "nixpkgs-hammering"
          "alejandra"
          "nixpkgs-fmt"
          "nixfmt"
        ];
        hasBanned = pkg: lib.elem (pkg.pname or (builtins.parseDrvName pkg.name).name) bannedPackages;
        foundBanned = lib.filter hasBanned config.environment.systemPackages;
      in
      [
        {
          assertion = foundBanned == [ ];
          message = "KRITISCHER FEHLER [POLICY]: Verbotene Linter/Formatter in systemPackages gefunden. Erlaubt sind NUR: nixfmt-rfc-style, statix, deadnix, nil, nixd. Banned: nix-linter, nixpkgs-lint, nixpkgs-hammering, alejandra, nixpkgs-fmt, nixfmt (legacy).";
        }
      ]
    );
  };
}
