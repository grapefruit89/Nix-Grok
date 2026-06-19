# Schicht B — Whitelist: Hardware/Module die ein normaler Mensch 2010–2025 verbaut.
# Assertion: host-requiredModules ⊆ whitelist ∪ host.whitelistExtra
{
  storage = [
    "ahci"
    "libata"
    "sd_mod"
    "sr_mod"
    "scsi_mod"
    "nvme"
    "nvme_core"
    "dm_mod"
    "dm_crypt"
    "md_mod"
    "loop"
  ];

  usb = [
    "xhci_pci"
    "ehci_pci"
    "ohci_pci"
    "usbcore"
    "usb_storage"
    "usbhid"
    "hid"
    "uas"
  ];

  netCommon = [
    "e1000e"
    "igc"
    "igb"
    "r8169"
    "r8125"
    "tg3"
    "bnx2"
    "forcedeth"
    "stmmac"
    "realtek"
  ];

  wireless = [
    "iwlwifi"
    "iwlmvm"
    "iwldvm"
    "iwlmei"
    "ath10k"
    "ath10k_pci"
    "ath11k"
    "ath12k"
    "rtw88"
    "rtw89"
    "mt76"
    "brcmfmac"
  ];

  gpu = [
    "i915"
    "amdgpu"
    "radeon"
    "nouveau"
  ];

  virt = [
    "kvm"
    "kvm_intel"
    "kvm_amd"
    "vhost"
    "vhost_net"
    "tun"
    "veth"
    "bridge"
  ];

  platformIntel = [
    "mei_me"
    "mei_txe"
    "intel_pch_thermal"
    "intel_powerclamp"
    "intel_rapl_common"
    "intel_rapl_msr"
  ];

  platformAmd = [
    "k10temp"
    "zenpower"
  ];

  misc = [
    "zram"
    "fuse"
    "configfs"
    "autofs4"
    "ntfs3"
    "ntfs"
  ];
}
