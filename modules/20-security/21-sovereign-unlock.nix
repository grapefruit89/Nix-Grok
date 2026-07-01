# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Sovereign Unlock LUKS-Kaskade (TPM2 / Tang / FIDO2 / initrd-SSH)
#   docs:
#     - docs/SECURITY.md
#   tags:
#     - security
#     - luks
#     - initrd
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgUnlock = config.my.security.sovereign-unlock;

  # Emergency QR-Code Script
  qrFallbackScript = pkgs.writeShellScript "nms-qr-fallback" ''
    set -euo pipefail
    sleep 30
    if [ -e /dev/mapper/sovereign_vault ] 2>/dev/null; then
      exit 0
    fi
    IP=$(ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    SSH_CMD="ssh -p ${toString cfgUnlock.sshPort} root@''${IP:-<server-ip>}"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     NMS v4.2 - SOVEREIGN IDENTITY FALLBACK              ║"
    echo "║                                                          ║"
    echo "║  Automatischer Unlock fehlgeschlagen.                   ║"
    echo "║  Bitte einen der folgenden Wege nutzen:                 ║"
    echo "║                                                          ║"
    echo "║  1. YubiKey einstecken und berühren                     ║"
    echo "║  2. Per SSH entsperren (QR-Code scannen):               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    ${pkgs.qrencode}/bin/qrencode -t ANSIUTF8 "$SSH_CMD"
    echo ""
    echo "  SSH: $SSH_CMD"
    echo "  Dann: systemd-tty-ask-password-agent"
  '';
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security.sovereign-unlock = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.mode == "production";
      description = "Sovereign Unlock LUKS cascade (TPM2/Tang/FIDO2/initrd-SSH)";
    };
    luksDevice = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "LUKS device path (set in machines/<host>/profile.nix).";
    };
    tangServer = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    sshPort = lib.mkOption {
      type = lib.types.int;
      default = 2222;
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    hostKey = lib.mkOption {
      type = lib.types.str;
      default = "/persist/etc/ssh/ssh_host_ed25519_key";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgUnlock.enable {
    boot = {
      initrd = {
        systemd.enable = true;

        luks.devices."sovereign_vault" = {
          device = cfgUnlock.luksDevice;
          crypttabExtraOpts = [
            "tpm2-device=auto"
            "tpm2-pcrs=0+1+7"
            "fido2-device=auto"
            "fido2-with-client-pin=false"
          ];
        };

        clevis = lib.mkIf (cfgUnlock.tangServer != "") {
          enable = true;
          devices."sovereign_vault".secretFile = "/run/nms-network-trusted";
        };

        network = {
          enable = true;
          ssh = lib.mkIf (cfgUnlock.authorizedKeys != [ ]) {
            enable = true;
            port = cfgUnlock.sshPort;
            inherit (cfgUnlock) authorizedKeys;
            hostKeys = [ cfgUnlock.hostKey ];
            shell = "${pkgs.writeShellScript "initrd-unlock-shell" ''
              echo "NMS v4.2 - Remote initrd Unlock Shell"
              echo "Unlock command: systemd-tty-ask-password-agent"
              exec ${pkgs.bashInteractive}/bin/bash
            ''}";
          };
        };

        systemd.services.nms-qr-fallback = {
          description = "NMS Emergency TTY QR-Code Fallback";
          wantedBy = [ "initrd.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = qrFallbackScript;
            RemainAfterExit = false;
          };
        };

        availableKernelModules = [
          "xhci_pci"
          "ehci_pci"
          "xhci_hcd"
          "usb_storage"
          "uas"
          "r8169"
          "e1000e"
          "igb"
          "ixgbe"
          "tg3"
          "atlantic"
          "r8152"
          "ax88179_178a"
          "cdc_ether"
          "tpm_tis"
          "tpm_crb"
          "tpm_tis_core"
          "dm_crypt"
          "aes"
        ];
      };
    };

    assertions = [
      {
        assertion = cfgUnlock.authorizedKeys != [ ] || cfgUnlock.tangServer != "";
        message = "Sovereign Unlock: Entweder initrd SSH-Keys oder ein Tang-Server müssen konfiguriert sein.";
      }
    ];
  };
}
