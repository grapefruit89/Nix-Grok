# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Host-spezifische Kernel-Slim-Policy für q958
#   lib:
#     - lib/kernel/policy.nix
#   tags:
#     - kernel-slim
# ---
{
  config,
  lib,
  pkgs,
  ...
}: let
  p = import ./profile.nix;
  k = p.kernel;
  cfg = config.my.core.kernel-slim;
  policy = import ../../lib/kernel/policy.nix {inherit lib;};

  policyInput = {
    mode = k.policy.mode;
    homelabProfile = k.policy.homelabProfile;
    inherit (k) requiredModules;
    inherit (k) requiredInitrdModules;
    hostBlacklist = lib.flatten (lib.attrValues k.blacklist);
    inherit (k) whitelistExtra;
    inherit (k) moduleRoles;
    hostLabel = "q958";
  };

  resolved = policy.compute policyInput;
in {
  config = {
    my.core.kernel-slim = {
      mode = lib.mkDefault k.policy.mode;
      homelabProfile = lib.mkDefault k.policy.homelabProfile;
    };

    boot.kernelPackages = lib.mkIf cfg.enable pkgs.linuxPackages_latest;
    boot.blacklistedKernelModules = lib.mkIf cfg.enable resolved.safeBlacklist;
    boot.kernelModules = lib.mkIf cfg.enable (lib.mkAfter k.requiredModules);
    boot.initrd.availableKernelModules = lib.mkIf cfg.enable (lib.mkAfter k.requiredInitrdModules);

    hardware.enableRedistributableFirmware = lib.mkIf cfg.enable (lib.mkForce false);
    hardware.firmware = lib.mkIf cfg.enable (lib.mkForce [pkgs.linux-firmware]);

    assertions = lib.mkIf cfg.enable resolved.assertions;
  };
}
