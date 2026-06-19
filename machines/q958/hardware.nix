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
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = p.hardware.initrdModules;
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ p.hardware.kvmModule ];
  boot.extraModulePackages = [ ];

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/${boot.label}";
    fsType = boot.fsType;
    options = [
      "fmask=${boot.fmask}"
      "dmask=${boot.dmask}"
    ];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/${persist.label}";
    fsType = persist.fsType;
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
