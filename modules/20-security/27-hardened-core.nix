# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Headless Service-Slimming und hideProcessInformation (Production)
#   docs:
#     - docs/guides/GUIDE-security-secrets.md
#   docs:
#     - docs/adr/2026-kernel-hardening-sysctl.md
#     - docs/guides/GUIDE-kernel-hardening.md
#   tags:
#     - security
#     - hardening
#     - headless
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.security.hardened;
in
{
  options.my.security.hardened = {
    enable = lib.mkEnableOption "Headless hardened core — disable desktop services, hide process info";

    lockKernelModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Lock kernel module loading after boot — active by default at stufe 9 (ADR-2026).";
    };
  };

  config = lib.mkIf cfg.enable {
    security.hideProcessInformation = true;
    security.lockKernelModules = cfg.lockKernelModules;

    boot.kernelParams = lib.mkIf cfg.lockKernelModules [ "lockdown=confidentiality" ];

    # YubiKey / FIDO2 für LUKS-Unlock
    services.pcscd.enable = lib.mkForce true;

    systemd.services = {
      accounts-daemon.enable = lib.mkForce false;
      ModemManager.enable = lib.mkForce false;
      udisks2.enable = lib.mkForce false;
      upower.enable = lib.mkForce false;
      cups.enable = lib.mkForce false;
      bluetooth.enable = lib.mkForce false;
      wpa_supplicant.enable = lib.mkForce false;
    };

    systemd.services.plymouth-quit-wait.enable = lib.mkForce false;

    # Headless-Server: systemd-networkd-wait-online blockiert jeden nixos-rebuild switch
    # für 2 Minuten (→ exit code 4). Root Cause (nixpkgs networkd.nix):
    #   networking.wg-quick.interfaces.privado setzt automatisch ignoredInterfaces = ["privado"]
    #   UND das networkd-Modul setzt wantedBy = ["network-online.target"] unconditional —
    #   unabhängig von systemd.network.wait-online.enable.
    # Fix: enable=false unterdrückt die Unit-Config; mkForce [] entfernt das WantedBy-Symlink.
    # Beide Zeilen sind nötig — allein reicht keine. (→ ADR-2030)
    systemd.network.wait-online.enable = false;
    systemd.services."systemd-networkd-wait-online".wantedBy = lib.mkForce [ ];
  };
}
