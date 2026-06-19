# Schicht B — Homelab-Headless-Server (kein WiFi, kein BT, kein Audio, keine Webcams)
{
  wireless = [
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

  bluetooth = [
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

  audio = [
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

  multimedia = [
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
}
