# Kernel-Slimming für Fujitsu Esprimo Q958 (i3-9100, Q370, I219-LM, UHD 630).
#
# Strategie:
#   1. Pflichtmodule (Whitelist) — Hardware die wir haben + brauchen
#   2. Blacklist nach Kategorien — alles was der Q958 nicht hat
#   3. Intel vor Kaby Lake (7. Gen) — Treiber für alte Intel-HW verbieten
#   4. Assertions — Build bricht wenn ein Pflichtmodul geblacklistet wird
#
{ config, lib, pkgs, ... }:

let
  cfg = config.my.core.kernel-slim;

  # ── WHITELIST: Q958-Hardware + Homelab-Bedarf ─────────────────────────────
  requiredKernelModules = [
    # Netz — Intel I219-LM (Onboard)
    "e1000e"
    # Grafik — UHD 630 (Jellyfin VA-API)
    "i915"
    # Storage — interne SATA-SSD
    "ahci"
    "sd_mod"
    "libata"
    "scsi_mod"
    # USB — Tastatur, Config-Stick, externe Disks
    "xhci_pci"
    "usb_storage"
    "usbhid"
    "hid"
    # Virtualisierung
    "kvm"
    "kvm_intel"
    # ZRAM-Swap
    "zram"
    # Intel Platform — Q370 / Coffee Lake PCH
    "mei_me"
    "intel_pch_thermal"
  ];

  requiredInitrdKernelModules = [
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
  ];

  # ── BLACKLIST: Intel vor Kaby Lake (7. Gen) — nicht im Q958 (9. Gen) ───────
  # Regel: alles vor i7-7xxx / i3-7100 ist verboten. Module die auch neuere
  # Chips bedienen (e1000e, i915) stehen in der Whitelist und werden nie geblacklistet.
  blacklistIntelPreKabyLake = [
    "e100" # PRO/100 10/100 Mbit
    "eepro100"
    "e1000" # PRO/1000 8254x — NICHT e1000e
    "igb" # 82575/82576 PCIe (Westmere/Sandy Bridge)
    "igbvf"
    "ixgbe" # 82598/82599 10G (Sandy/Ivy Bridge Server)
    "ixgbevf"
    "ipw2100"
    "ipw2200"
    "iwl3945"
    "iwl4965"
    "iwlwifi"
    "iwldvm"
    "iwlmvm"
    "iwlmei"
    "snd_intel8x0" # AC97-Audio (vor HDA)
  ];

  # ── BLACKLIST: Datacenter / Server-NICs (nicht Onboard-Desktop) ───────────
  blacklistDatacenterNet = [
    "i40e"
    "i40evf"
    "ice"
    "fm10k"
    "igc"
    "mlx4_core"
    "mlx4_en"
    "mlx5_core"
    "mlx5_ib"
    "bnxt_en"
    "bnxt_re"
    "qede"
    "qed"
    "liquidio"
    "ionic"
    "sfc"
    "sfc-falcon"
    "sfc-siena"
    "be2net"
    "bna"
    "enic"
    "vmxnet3"
    "mana"
    "ntb_netdev"
    "jme"
    "atl1c"
    "atl1e"
    "atl2c"
    "sky2"
  ];

  # ── BLACKLIST: Enterprise Storage / HW-RAID (kein Controller im Q958) ───────
  blacklistEnterpriseStorage = [
    "megaraid_sas"
    "mpt3sas"
    "mpt2sas"
    "mptspi"
    "mptscsih"
    "aacraid"
    "hpsa"
    "smartpqi"
    "3w-xxxx"
    "3w-9xxx"
    "aic7xxx"
    "aic79xx"
    "sym53c8xx"
    "sym53c8xx_2"
    "BusLogic"
    "qla2xxx"
    "lpfc"
    "bnxt_fc"
    "bfa"
    "mptfc"
    "xen-blkfront"
    "xen-scsifront"
    "virtio_blk"
    "virtio_scsi"
  ];

  # ── BLACKLIST: Fibre Channel / Infiniband / RDMA ───────────────────────────
  blacklistHpcInterconnect = [
    "ib_core"
    "ib_ipoib"
    "ib_umad"
    "ib_uverbs"
    "ib_cm"
    "rdma_cm"
    "rdma_ucm"
    "rpcrdma"
    "mlx4_ib"
    "mlx5_ib"
    "siw"
    "mana_ib"
  ];

  # ── BLACKLIST: Drahtlos (kein WiFi-Chip im Q958) ──────────────────────────
  blacklistWireless = [
    "ath9k"
    "ath9k_htc"
    "ath9k_common"
    "ath10k"
    "ath10k_pci"
    "ath11k"
    "ath12k"
    "ath6kl"
    "rtw88"
    "rtw89"
    "rtw88pci"
    "rtw88usb"
    "rtl8192ce"
    "rtl8192c_common"
    "rtl8192cu"
    "rtl8187"
    "rtl8xxxu"
    "mt76"
    "mt7601u"
    "mt76x0u"
    "mt76x2u"
    "brcmfmac"
    "brcmutil"
    "mwifiex"
    "mwifiex_pcie"
    "rsi_91x"
    "wl"
    "b43"
    "b43legacy"
    "bcma"
    "ssb"
    "mac80211_hwsim"
  ];

  # ── BLACKLIST: Bluetooth (Headless, kein BT-Chip) ─────────────────────────
  blacklistBluetooth = [
    "bluetooth"
    "btusb"
    "btrtl"
    "btbcm"
    "btintel"
    "btsdio"
    "bnep"
    "rfcomm"
    "hidp"
  ];

  # ── BLACKLIST: Audio (Headless Server) ────────────────────────────────────
  blacklistAudio = [
    "snd_hda_intel"
    "snd_hda_codec_hdmi"
    "snd_hda_codec"
    "snd_hda_core"
    "snd_soc_skl"
    "snd_soc_avs"
    "snd_usb_audio"
    "snd_seq"
    "snd_pcm"
  ];

  # ── BLACKLIST: Multimedia / Consumer-Exoten ───────────────────────────────
  blacklistMultimedia = [
    "uvcvideo"
    "gspca_main"
    "gspca_sonixj"
    "videodev"
    "v4l2_common"
    "dvb_core"
    "dvb_usb"
    "media"
    "rc_core"
    "lirc_dev"
  ];

  # ── BLACKLIST: Legacy-Busse / tot ─────────────────────────────────────────
  blacklistLegacyBus = [
    "floppy"
    "parport"
    "parport_pc"
    "ppdev"
    "firewire-ohci"
    "firewire-sbp2"
    "pcmcia"
    "yenta_socket"
    "ide"
    "ide_pci_generic"
    "pata_oldpiix"
    "pata_amd"
    "ne2k-pci"
    "8139too"
    "8139cp"
    "tulip"
    "3c59x"
    "via-rhine"
    "via-velocity"
    "hamradio"
    "can"
    "vcan"
    "slcan"
  ];

  allBlacklist = lib.unique (
    blacklistIntelPreKabyLake
    ++ blacklistDatacenterNet
    ++ blacklistEnterpriseStorage
    ++ blacklistHpcInterconnect
    ++ blacklistWireless
    ++ blacklistBluetooth
    ++ blacklistAudio
    ++ blacklistMultimedia
    ++ blacklistLegacyBus
  );

  # Pflichtmodule dürfen nie auf der Blacklist landen (Programmierfehler-Schutz)
  safeBlacklist = lib.filter (m: !(lib.elem m requiredKernelModules)) allBlacklist;
in
{
  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.blacklistedKernelModules = safeBlacklist;

    boot.kernelModules = lib.mkAfter requiredKernelModules;

    boot.initrd.availableKernelModules = lib.mkAfter requiredInitrdKernelModules;

    hardware.enableRedistributableFirmware = lib.mkForce false;
    hardware.firmware = lib.mkForce [
      pkgs.linux-firmware # i915 / Intel GPU
    ];

    assertions =
      (map
        (m: {
          assertion = !(lib.elem m safeBlacklist);
          message = "KERNEL-SICHERUNG: Pflichtmodul '${m}' steht in der Blacklist-Definition.";
        })
        requiredKernelModules)
      ++ (map
        (m: {
          assertion = !(lib.elem m safeBlacklist);
          message = "KERNEL-SICHERUNG: Initrd-Pflichtmodul '${m}' steht in der Blacklist-Definition.";
        })
        requiredInitrdKernelModules);
  };
}
