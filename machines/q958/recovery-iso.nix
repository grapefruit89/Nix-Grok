# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Zero-Touch Recovery-ISO — bootet und führt recover automatisch aus
#   tags:
#     - recovery
#     - iso
# ---
{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  c = import ./recovery-constants.nix;
  rootHashedPassword = lib.removeSuffix "\n" (
    builtins.readFile (
      pkgs.runCommandLocal "q958-recovery-root-hash" { nativeBuildInputs = [ pkgs.mkpasswd ]; } ''
        printf '%s' '${c.ssh.rootPassword}' | mkpasswd -m sha-512 -s > $out
      ''
    )
  );
  manifest = pkgs.writeText "manifest.env" ''
    RECOVERY_MODE=${c.recovery.mode}
    RECOVERY_DISK_BY_ID=${c.disk.deviceById}
    RECOVERY_ROOT_DEV=${c.disk.root}
    RECOVERY_ESP_DEV=${c.disk.esp}
    RECOVERY_ESP_LABEL=${c.disk.espLabel}
    RECOVERY_USB_LABEL=${c.usb.dataLabel}
    RECOVERY_AUTO_REBOOT=${if c.recovery.autoReboot then "1" else "0"}
    RECOVERY_REBOOT_DELAY_SEC=${toString c.recovery.rebootDelaySec}
    RECOVERY_INTERFACE=${c.network.interface}
  '';

  bootstrap = ../../scripts/emergency-bootstrap-q958.sh;
  manifestLib = ../../scripts/lib/recovery-manifest.sh;

  recoveryMotd = pkgs.writeText "recovery-motd" ''
    ╔══════════════════════════════════════════════════════════╗
    ║  q958 RECOVERY LIVE — SSH aktiv (Zero-Touch läuft)       ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Fortschritt live:                                        ║
    ║    journalctl -fu q958-auto-recover.service               ║
    ║    tail -f /run/q958-recovery/recover.log                 ║
    ║  Host: ${c.network.ip}  User: root  Passwort: ${c.ssh.rootPassword}       ║
    ╚══════════════════════════════════════════════════════════╝
  '';

  autoRecover = pkgs.writeShellScript "q958-auto-recover" ''
    set -euo pipefail
    mkdir -p /run/q958-recovery /recovery /run/q958-recovery/lib
    cp ${manifest} /run/q958-recovery/manifest.env
    cp ${manifest} /recovery/manifest.env
    export RECOVERY_MANIFEST=/recovery/manifest.env
    install -Dm755 ${bootstrap} /run/q958-recovery/emergency-bootstrap-q958.sh
    install -Dm755 ${manifestLib} /run/q958-recovery/lib/recovery-manifest.sh
    {
      echo "╔══════════════════════════════════════════════════════════╗"
      echo "║  q958 ZERO-TOUCH RECOVERY — startet automatisch           ║"
      echo "║  Modus: recover (Store behalten) — NICHT install          ║"
      echo "╠══════════════════════════════════════════════════════════╣"
      echo "║  SSH (vom Hauptrechner): root@${c.network.ip}               ║"
      echo "║  Passwort: ${c.ssh.rootPassword}   journalctl -fu q958-auto-recover   ║"
      echo "╚══════════════════════════════════════════════════════════╝"
    } > /dev/tty1
    exec /run/q958-recovery/emergency-bootstrap-q958.sh recover
  '';
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.hostName = lib.mkForce "q958-recovery";
  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = lib.mkForce true;

  systemd.network.networks.${c.network.systemdNetworkName} = {
    matchConfig.Name = c.network.interface;
    networkConfig = {
      Address = "${c.network.ip}/${toString c.network.prefixLength}";
      Gateway = c.network.gateway;
      DNS = [ "192.168.2.1" ];
    };
  };

  services.openssh = lib.mkIf c.ssh.enable {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
  };

  users.users.root.hashedPassword = lib.mkIf c.ssh.enable (lib.mkForce rootHashedPassword);

  environment.etc.motd.text = lib.mkForce (builtins.readFile recoveryMotd);

  isoImage = {
    isoName = "${c.usb.isoLabel}.iso";
    volumeID = c.usb.isoLabel;
    makeUsbBootable = true;
    contents = [
      {
        source = manifest;
        target = "/recovery/manifest.env";
      }
    ];
  };

  systemd.services.q958-auto-recover = {
    description = "q958 Zero-Touch Recovery (recover only)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "sshd.service"
      "systemd-networkd.service"
      "local-fs.target"
    ];
    wants = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = autoRecover;
      StandardOutput = "journal+console";
      StandardError = "journal+console";
      RemainAfterExit = true;
    };
  };

  services.getty.autologinUser = lib.mkForce "root";
}
