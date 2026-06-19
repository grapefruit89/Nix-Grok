# Schicht A — Dateisystem-Module die im Homelab nicht gebraucht werden.
# ext4/btrfs/vfat/f2fs/ntfs sind Standard; der Rest ist Exot / Enterprise / tot.
[
  "reiserfs"
  "jfs"
  "gfs2"
  "gfs2_meta"
  "ocfs2"
  "ocfs2_stackglue"
  "ocfs2_dlm"
  "ceph"
  "orangefs"
  "befs"
  "minix"
  "sysv"
  "ufs"
  "hfs"
  "hfsplus"
  "affs"
  "qnx4"
  "qnx6"
  "nilfs2"
  "cramfs"
  "freevxfs"
  "efs"
  "adfs"
  "bfs"
  
  # Added per ADR to keep it KISS and avoid unnecessary attack vectors
  "btrfs"
  "ntfs"
]
