# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Tier-A Partitionsschema q958 — GPT, NIXBOOT (vfat) + NIXPERSIST (ext4), nur ext4
#   docs:
#     - docs/guides/GUIDE-storage-tiers.md
#     - docs/adr/3024-disko-tier-a-provisioning.md
#     - machines/q958/profile.nix
#   tags:
#     - disko
#     - tier-a
#     - dr
# ---
# SSoT für Systemplatte. Werte aus profile.nix — nicht duplizieren.
#
# Stufe 0–8 (aktuell): NIXPERSIST → /
# Stufe 9 (Impermanence, später): NIXPERSIST → /persist, tmpfs / via 30-storage.nix
#
# Learning (ADR-3024):
#   1. CLI: install = --mode destroy,format,mount (NICHT --mode disko)
#   2. ESP: profile.nix boot.espSize (512M). generationLimit ≠ ESP-Größe (GUIDE-boot-esp.md)
#   3. Nach Reinstall: diskoManaged=true → verify → prune (disko-deprecations.json)
#
# DR / Neuinstallation (ZERSTÖRT Daten auf der Zielplatte!):
#   sudo /etc/nixos/scripts/disko-q958.sh install
#   sudo nixos-install --flake /etc/nixos#q958 --impure --no-root-passwd
#
# Laufendes q958: hardware.nix mountet by-label — disko-Modul erst wenn diskoManaged.
#
# Layout prüfen (ohne Schreiben): disko-q958.sh plan  (Alias: disko-plan) — NIEMALS "disko script"!
#
# vs. single-disk-ext4-Template (nix-community/disko-templates):
#   • Kein 1M EF02 BIOS-Partition (systemd-boot/EFI-only)
#   • ESP 512M statt 1G; Labels NIXBOOT/NIXPERSIST statt generisch
#   • deviceById statt /dev/sda; Partition-Namen = Label (disk-tierA-*)
{
  ...
}:
let
  p = import ./profile.nix;
  tierA = p.storage.tierA;
  boot = tierA.boot;
  persist = tierA.persist;
  # by-id bevorzugt (Template-Best-Practice); /dev/sda nur Fallback/Legacy
  tierADevice = tierA.deviceById or tierA.device;
in
{
  disko.devices = {
    disk.tierA = {
      device = tierADevice;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = boot.label;
            # SSoT: profile.nix storage.tierA.boot.espSize (GUIDE-boot-esp.md)
            size = boot.espSize or "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = boot.fsType;
              extraArgs = [
                "-n"
                boot.label
              ];
              mountpoint = "/boot";
              mountOptions = [
                "fmask=${boot.fmask}"
                "dmask=${boot.dmask}"
              ];
            };
          };
          persist = {
            name = persist.label;
            size = "100%";
            content = {
              type = "filesystem";
              format = persist.fsType;
              extraArgs = [
                "-L"
                persist.label
              ];
              mountpoint = persist.mountPoint;
              mountOptions = [
                "defaults"
                "noatime"
              ];
            };
          };
        };
      };
    };
  };
}
