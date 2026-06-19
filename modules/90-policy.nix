{ config, lib, ... }:

{
  # ============================================================================
  # ZERO-TOLERANCE POLICY & FORBIDDEN TECHNOLOGY
  # ============================================================================
  config = lib.mkIf (config.my.mode == "production" || config.my.mode == "development") {

    # --- HARTE DEAKTIVIERUNGEN ---
    # Diese Dienste werden systemweit erzwungen deaktiviert.
    services.xserver.enable = lib.mkForce false;
    sound.enable = lib.mkForce false;
    hardware.pulseaudio.enable = lib.mkForce false;
    networking.networkmanager.enable = lib.mkForce false;

    # IPv6 Bann (Homelab Area)
    networking.enableIPv6 = lib.mkForce false;

    # Aus v5: Unnötige Desktop- und Peripherie-Daemons abschalten
    services.accounts-daemon.enable = lib.mkForce false;
    services.upower.enable = lib.mkForce false;
    services.printing.enable = lib.mkForce false; # cups
    hardware.bluetooth.enable = lib.mkForce false;
    networking.wireless.enable = lib.mkForce false; # wpa_supplicant

    # --- KERNEL & PROCESS SECURITY ---
    security.hideProcessInformation = true;

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
        assertion = config.nixpkgs.overlays == [ ];
        message = "KRITISCHER FEHLER [POLICY]: Globale nixpkgs.overlays sind verboten. Nutze lokale Package-Inputs zur Vermeidung von Supply-Chain-Risiken und Rebuild-Stürmen.";
      }
    ];
  };
}

