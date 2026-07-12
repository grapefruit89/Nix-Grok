# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Minimale NixOS-VM nur für disko-Lernen (vmWithDisko) — kein profile.local
#   docs:
#     - docs/guides/GUIDE-disko-learning.md
#   tags:
#     - disko
#     - vm
# ---
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  networking.hostName = "q958-disko-vm";
  system.stateVersion = "26.05";

  # disko-vm nutzt /dev/vda statt SATA — siehe disko-vm.nix
  virtualisation.vmVariantWithDisko = {
    virtualisation.diskSize = 2048;
  };
}
