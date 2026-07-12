# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: disko-Layout für VM-Tests (/dev/vda) — Spiegel von disko.nix ohne profile.local
#   docs:
#     - docs/guides/GUIDE-disko-learning.md
#   tags:
#     - disko
#     - vm
# ---
{
  disko.devices = {
    disk.tierA = {
      device = "/dev/vda";
      type = "disk";
      imageSize = "2G";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "NIXBOOT";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [
                "-n"
                "NIXBOOT"
              ];
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0022"
                "dmask=0022"
              ];
            };
          };
          persist = {
            name = "NIXPERSIST";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              extraArgs = [
                "-L"
                "NIXPERSIST"
              ];
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
}
