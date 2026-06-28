# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Kernel-Blacklist Schicht A — exotische Dateisysteme
#   tags:
#     - kernel
#     - blacklist
# ---
# Erlaubt (whitelist-homelab.nix): ext4, vfat, fat, ntfs3, fuse, squashfs, overlay
# squashfs NICHT blacklisten — NixOS braucht es für den Nix-Store
[
  # Cluster-Dateisysteme (kein SAN/Ceph im Homelab)
  "gfs2"
  "gfs2_meta"
  "ocfs2"
  "ocfs2_stackglue"
  "ocfs2_dlm"
  "ceph"
  "orangefs"

  # Häufige Linux-Alternativen — nicht in Nutzung (ZFS + mergerfs + ext4)
  "xfs"
  "btrfs"
  "f2fs"
  "nilfs2"
  "reiserfs"
  "jfs"

  # Wechselmedien / optische Medien
  "exfat"
  "isofs"
  "udf"

  # Flash/Embedded-Dateisysteme
  "jffs2"
  "erofs"
  "romfs"
  "cramfs"

  # Legacy UNIX / Antike Systeme
  "minix"
  "sysv"
  "ufs"
  "befs"
  "affs"
  "qnx4"
  "qnx6"
  "freevxfs"
  "efs"
  "adfs"
  "bfs"

  # macOS-Dateisysteme
  "hfs"
  "hfsplus"
]
