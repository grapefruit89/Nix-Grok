# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Storage-Tier-Assertions und Automount-Optionen q958
#   tags:
#     - storage
#     - tier-policy
# ---
{ config, lib, pkgs, ... }:

let
  p = import ./profile.nix;
  s = p.storage;
  tp = s.tierPolicy;
in
{
  assertions = [
    {
      assertion = !(s.singleDisk && s.mergerfsEnable);
      message = "q958 singleDisk: mergerfsEnable bleibt false bis NIXDATA/NIXMEDIA-Branches existieren.";
    }
    {
      assertion = tp.a.medium == "ssd" && tp.b.medium == "ssd";
      message = "Tier A und Tier B: SSD only — kein spinning device.";
    }
    {
      assertion = tp.c.medium == "hdd";
      message = "Tier C: HDD only (cold storage).";
    }
    {
      assertion = lib.elem "ata" tp.b.bus && !(lib.elem "nvme" tp.b.bus);
      message = "Tier B: immer SATA — nie NVMe, nie HDD.";
    }
    {
      assertion = lib.elem "nvme" tp.a.bus || lib.elem "ata" tp.a.bus;
      message = "Tier A: NVMe bevorzugt, SATA erlaubt wenn keine NVMe.";
    }
  ];

  # singleDisk ohne Tier B/C: Media-Pfade als Stub (bis NIXDATA/NIXMEDIA da sind)
  systemd.tmpfiles.rules = lib.mkIf s.singleDisk [
    "d /data/media 0775 root media -"
    "d /data/downloads 0775 root media -"
    "d /mnt/fast_pool/cache/jellyfin 0775 jellyfin media -"
    "d /mnt/fast_pool/metadata/jellyfin 0775 jellyfin media -"
    "d /mnt/fast_pool/metadata/sonarr 0775 sonarr media -"
    "d /mnt/fast_pool/metadata/radarr 0775 radarr media -"
    "d /mnt/fast_pool/metadata/prowlarr 0775 prowlarr media -"
    "d /mnt/fast_pool/metadata/readarr 0775 readarr media -"
  ];

  my.services.storage-automount = {
    singleDisk = s.singleDisk;
    tierADevice = s.tierA.device;
    systemLabels = s.systemLabels;
    tierBLabel = s.tierB.label;
    tierCLabels = s.tierC.labels;
  };

  # Einmal-Migration: BOOT/NIXHOME_PERSIST → NIXBOOT/NIXPERSIST
  system.activationScripts.relabelTierALabels = lib.stringAfter [ "specialfs" ] ''
      boot_dev="${s.tierA.device}1"
      persist_dev="${s.tierA.device}2"
      if [ -b "$boot_dev" ]; then
        boot_label=$(${pkgs.util-linux}/bin/lsblk -no LABEL "$boot_dev" 2>/dev/null || true)
        if [ "$boot_label" = "BOOT" ]; then
          echo "relabelTierALabels: BOOT → NIXBOOT on $boot_dev"
          ${pkgs.dosfstools}/bin/fatlabel "$boot_dev" NIXBOOT
        fi
      fi
      if [ -b "$persist_dev" ]; then
        persist_label=$(${pkgs.util-linux}/bin/lsblk -no LABEL "$persist_dev" 2>/dev/null || true)
        if [ "$persist_label" = "NIXHOME_PERSIST" ]; then
          echo "relabelTierALabels: NIXHOME_PERSIST → NIXPERSIST on $persist_dev"
          ${pkgs.e2fsprogs}/bin/e2label "$persist_dev" NIXPERSIST
        fi
      fi
  '';
}