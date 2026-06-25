# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Feste systemd-boot-Baseline-Generationen 85/86
#   tags:
#     - boot
#     - baseline
# ---
{ config, lib, pkgs, ... }:

let
  p = import ./profile.nix;
  machineId = "e62778ec1b5b4a23850bb783b7b61a12";
  linuxEfi = "/EFI/nixos/k3c378ybgwrx5k5216z6s3ki12kav2xv-linux-7.0.10-bzImage.efi";
  initrdEfi = "/EFI/nixos/krc3yn0vkfaxbysaddpwpn8h6z7q4ygv-initrd-linux-7.0.10-initrd.efi";
  kernelParams = lib.concatStringsSep " " p.boot.kernelParams;
in
{
  boot.loader.systemd-boot.extraEntries = {
    "q958-baseline-gen85.conf" = ''
      title Baseline (Gen 85)
      sort-key 0_archiv_85
      version Baseline Generation 85 — gepinnt
      linux ${linuxEfi}
      initrd ${initrdEfi}
      options init=/nix/store/rx48zvsgclfga6pif9kr6l8b46sm2qgw-nixos-system-q958-26.11.20260531.331800d/init ${kernelParams} root=fstab loglevel=4 lsm=landlock,yama,bpf
      machine-id ${machineId}
    '';
    "q958-baseline-gen86.conf" = ''
      title Baseline (Gen 86)
      sort-key 0_archiv_86
      version Baseline Generation 86 — gepinnt
      linux ${linuxEfi}
      initrd ${initrdEfi}
      options init=/nix/store/fhzb1zi81ya7g513yn142cjssx5aixfn-nixos-system-q958-26.11.20260531.331800d/init ${kernelParams} root=fstab loglevel=4 lsm=landlock,yama,bpf
      machine-id ${machineId}
    '';
  };

  systemd.services.q958-pin-baseline-boot = {
    description = "Baseline-Boot-Einträge schreibgeschützt (nach systemd-boot-update)";
    after = [ "systemd-boot-update.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "q958-pin-baseline-boot" ''
        set -euo pipefail
        for f in /boot/loader/entries/q958-baseline-gen*.conf; do
          [ -f "$f" ] || continue
          ${pkgs.e2fsprogs}/bin/chattr -i "$f" 2>/dev/null || true
          chmod 444 "$f"
          ${pkgs.e2fsprogs}/bin/chattr +i "$f" 2>/dev/null || true
        done
      '';
    };
  };
}