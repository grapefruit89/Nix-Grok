from pathlib import Path

path = Path("/etc/nixos/modules/00-core.nix")
text = path.read_text()

if "./kernel-slim-q958.nix" not in text:
    text = text.replace(
        "in\n\n{\n  # ============================================================================\n  # OPTIONS",
        "in\n\n{\n  imports = [ ./kernel-slim-q958.nix ];\n\n  # ============================================================================\n  # OPTIONS",
        1,
    )

old = """    # ── KERNEL SLIMMING ───────────────────────────────────────────────────────
    (lib.mkIf cfgKernel.enable {
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # Deaktiviere ungenutzte Module zur CPU- und RAM-Entlastung
      boot.blacklistedKernelModules = [
        # Bluetooth (ungenutzt auf Headless Server)
        "bluetooth"
        "btusb"
        "btrtl"
        "btbcm"
        "btintel"
        # Legacy/Ungenutztes WiFi
        "iwlwifi"
        "ath9k"
        "rtl8192ce"
        # Audio / Sound-Hardware (ungenutzt)
        "snd_hda_intel"
        "snd_hda_codec_hdmi"
      ];

      # Lade nur unbedingt erforderliche Firmware
      hardware.enableRedistributableFirmware = lib.mkForce false;
      hardware.firmware = lib.mkForce [
        pkgs.linux-firmware # Erforderlich für Intel UHD 630 i915 Treiber
      ];
    })

"""
if old not in text:
    raise SystemExit("kernel slim block not found")
text = text.replace(old, "    # ── KERNEL SLIMMING → modules/kernel-slim-q958.nix\n\n")
path.write_text(text)
print("patched ok")