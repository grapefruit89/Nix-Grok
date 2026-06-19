{ config, lib, ... }:

let
  p = import ./profile.nix;
in
{
  disko.devices = {
    disk = {
      # Tier-A: Main System Drive (Dynamic mapping via profile.nix)
      tier_a = {
        type = "disk";
        # Dieser Wert liest automatisch /dev/nvme0n1 oder /dev/sda aus deiner profile.nix!
        device = p.storage.tierA.device;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              name = "luks_root";
              size = "100%";
              content = {
                type = "luks";
                name = "sovereign_vault";

                # ZERO-KNOWLEDGE STRATEGIE:
                # Disko liest bei der Installation das Passwort aus dieser temporären Datei im RAM aus.
                # Weder GitHub noch die KI kennen das Passwort.
                # Vor dem Ausführen von `disko` machst du einmalig:
                # echo -n "DeinGeheimesPasswort" > /tmp/luks_password.txt
                passwordFile = "/tmp/luks_password.txt";

                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
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
    };
  };
}
