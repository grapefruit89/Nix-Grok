# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Boot/Root-FS und Kernel-Module an Tier-A aus profile.nix
#   docs:
#     - docs/adr/3024-disko-tier-a-provisioning.md
#   tags:
#     - hardware
#     - tier-a
# ---
# Legacy fileSystems: entfernbar nach disko-Reinstall + diskoManaged=true + prune (Phase 3)
{
  config,
  lib,
  modulesPath,
  ...
}:
let
  p = import ./profile.nix;
  boot = p.storage.tierA.boot;
  persist = p.storage.tierA.persist;
  diskoManaged = p.storage.tierA.diskoManaged or false;
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd.availableKernelModules = p.hardware.initrdModules;
    # i915 früh laden → KMS bereits in Stage 1, schnellerer Framebuffer
    initrd.kernelModules = [ "i915" ];
    kernelModules = [ p.hardware.kvmModule ];
    extraModulePackages = [ ];
  };

  # DEPRECATED-DISKO-START: hardware-filesystems-legacy
  # Runtime-Mounts per FS-Label (Legacy-Platte). Nach disko-Reinstall: disko-enabled.nix
  fileSystems."/boot" = lib.mkIf (!diskoManaged) {
    device = "/dev/disk/by-label/${boot.label}";
    inherit (boot) fsType;
    options = [
      "fmask=${boot.fmask}"
      "dmask=${boot.dmask}"
    ];
  };

  fileSystems."/" = lib.mkIf (!diskoManaged) {
    device = "/dev/disk/by-label/${persist.label}";
    inherit (persist) fsType;
  };
  # DEPRECATED-DISKO-END: hardware-filesystems-legacy

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
