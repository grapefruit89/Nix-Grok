# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Boot/Root-FS und Kernel-Module an Tier-A aus profile.nix
#   tags:
#     - hardware
#     - tier-a
# ---
{
  config,
  lib,
  modulesPath,
  ...
}: let
  p = import ./profile.nix;
  boot = p.storage.tierA.boot;
  persist = p.storage.tierA.persist;
in {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    initrd.availableKernelModules = p.hardware.initrdModules;
    initrd.kernelModules = [];
    kernelModules = [p.hardware.kvmModule];
    extraModulePackages = [];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/${boot.label}";
    inherit (boot) fsType;
    options = [
      "fmask=${boot.fmask}"
      "dmask=${boot.dmask}"
    ];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/${persist.label}";
    inherit (persist) fsType;
  };

  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
