# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Headless Service-Slimming und hideProcessInformation (Production)
#   docs:
#     - docs/guides/GUIDE-security-secrets.md
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
      default = false;
      description = "Lock kernel module loading after boot (strict; test before enabling).";
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
    systemd.services."systemd-networkd-wait-online".enable = lib.mkForce false;
  };
}
