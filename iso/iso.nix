# q958 Rettungs- und Installations-Stick
#
# Ziel: Stick rein, booten, NICHTS tun. Kein Menue, kein Tastendruck,
# kein loadkeys, kein passwd, kein "systemctl start sshd".
# Danach genuegt am Prompt:  install
#
# Bauen:   nix build .#iso
# Schreiben:  dd if=result/iso/*.iso of=/dev/disk/by-id/<stick> bs=4M status=progress conv=fsync
{
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  # Login-Keys. Erster: Windows-Arbeitsrechner (~/.ssh/id_ed25519.pub).
  # Zweiter: aus users/jarvis/profile.nix -- damit derselbe Stick auch
  # gegen ein bereits installiertes q958 passt.
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvttE1EzwLJpzFc/LuuXZP485Ma0mEJQiu3iMXaO58W"
  ];

  # Bewusst im Klartext: Das Live-Medium haelt keine Daten und lebt bis zum
  # naechsten Reboot. Das Passwort schuetzt nichts -- es ist die Rueckfallebene
  # fuer die Konsole, falls der Key mal nicht greift.
  livePassword = "#baumeister";

  # ── Die Grundkonfiguration, die 'install' auf die Platte schreibt ─────────
  # Exakt der Stand, der auf q958 verifiziert laeuft: bootet, de-latin1,
  # sshd an, Keys hinterlegt. Bewusst minimal -- jedes zusaetzliche Modul
  # ist eine weitere Sache, die beim Installieren scheitern kann.
  baseConfig = pkgs.writeText "configuration.nix" ''
    { config, pkgs, ... }:
    {
      imports = [ ./hardware-configuration.nix ];

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.configurationLimit = 10;

      console.keyMap = "de-latin1";
      i18n.defaultLocale = "de_DE.UTF-8";
      time.timeZone = "Europe/Berlin";

      networking.hostName = "q958";
      networking.useDHCP = true;
      networking.firewall.enable = false;

      # Erreichbar als q958.local -- keine IP noetig, ueberlebt DHCP-Wechsel.
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        publish = { enable = true; addresses = true; };
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };
      };

      users.users.jarvis = {
        isNormalUser = true;
        description = "Mo";
        extraGroups = [ "wheel" "networkmanager" ];
        openssh.authorizedKeys.keys = [
    ${lib.concatMapStringsSep "\n" (k: "      \"${k}\"") authorizedKeys}
        ];
      };

      users.users.root.openssh.authorizedKeys.keys =
        config.users.users.jarvis.openssh.authorizedKeys.keys;

      # Kein Passwort gesetzt (nur Keys) -- ohne das waere sudo unbenutzbar.
      security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = with pkgs; [
        git vim curl wget ripgrep python3 e2fsprogs
        gptfdisk parted htop tmux pciutils usbutils
      ];

      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      system.stateVersion = "26.05";
    }
  '';

  # ── Der eine Befehl ───────────────────────────────────────────────────────
  install-q958 = pkgs.writeShellScriptBin "install" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath (with pkgs; [
        gptfdisk
        parted
        dosfstools
        e2fsprogs
        util-linux
        coreutils
        gnugrep
        gnused
      ])
    }:$PATH

    [[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"

    TARGET="''${1:-}"

    # Nur interne Platten anbieten. RM=1 sind Wechselmedien (der Stick, von
    # dem wir gerade laufen) -- die duerfen niemals Ziel sein.
    mapfile -t DISKS < <(lsblk -dnp -o NAME,RM,TYPE | awk '$2==0 && $3=="disk" {print $1}')

    if [[ -z "$TARGET" ]]; then
      if [[ ''${#DISKS[@]} -eq 1 ]]; then
        TARGET="''${DISKS[0]}"
        echo "Einzige interne Platte gefunden: $TARGET"
      else
        echo "Mehrere interne Platten. Bitte eine angeben:"
        for d in "''${DISKS[@]}"; do
          echo "   install $d      ($(lsblk -dno SIZE "$d"), $(lsblk -dno MODEL "$d"))"
        done
        exit 1
      fi
    fi

    [[ -b "$TARGET" ]] || { echo "$TARGET ist kein Blockgeraet."; exit 1; }

    # Sicherheitsnetz: niemals das Medium loeschen, von dem wir booten.
    BOOTDEV="$(findmnt -no SOURCE /iso 2>/dev/null || true)"
    if [[ -n "$BOOTDEV" && "$BOOTDEV" == "$TARGET"* ]]; then
      echo "ABBRUCH: $TARGET ist der Stick, von dem dieses System laeuft."
      exit 1
    fi

    echo ""
    echo "  Ziel:  $TARGET  ($(lsblk -dno SIZE "$TARGET"), $(lsblk -dno MODEL "$TARGET"))"
    echo "  ALLE DATEN DARAUF WERDEN GELOESCHT."
    read -rp "  Zum Bestaetigen 'ja' tippen: " ok
    [[ "$ok" == "ja" ]] || { echo "Abgebrochen."; exit 1; }

    echo ""
    echo "== 1/4  Partitionieren (ESP 1 GB) =="
    umount -R /mnt 2>/dev/null || true
    wipefs -a "$TARGET"
    sgdisk --zap-all "$TARGET"
    sgdisk --new=1:0:+1G --typecode=1:EF00 --change-name=1:ESP  "$TARGET"
    sgdisk --new=2:0:0   --typecode=2:8300 --change-name=2:root "$TARGET"
    partprobe "$TARGET"; sleep 3

    # p1/p2 bei NVMe, 1/2 bei SATA
    if [[ -b "''${TARGET}p1" ]]; then P1="''${TARGET}p1"; P2="''${TARGET}p2"
    else P1="''${TARGET}1"; P2="''${TARGET}2"; fi

    mkfs.fat -F32 -n BOOT "$P1"
    mkfs.ext4 -F -L nixos "$P2"

    echo "== 2/4  Einhaengen =="
    mount "$P2" /mnt
    mkdir -p /mnt/boot
    mount "$P1" /mnt/boot

    echo "== 3/4  Konfiguration schreiben =="
    nixos-generate-config --root /mnt
    install -m 0644 ${baseConfig} /mnt/etc/nixos/configuration.nix

    echo "== 4/4  Installieren (dauert ein paar Minuten) =="
    NIX_CONFIG='experimental-features = nix-command flakes' \
      nixos-install --no-root-passwd --no-channel-copy

    echo ""
    echo "  Fertig. Stick abziehen und neu starten:   reboot"
    echo "  Danach erreichbar unter:                  ssh jarvis@q958.local"
  '';
in
{
  imports = [
    # minimal = kein Desktop, schnell gebaut. Bootet BIOS und UEFI.
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # ── Kein Menue, kein Tastendruck ──────────────────────────────────────────
  # Das ISO-Modul setzt standardmaessig timeout = 10 (Zeile 1029 in
  # iso-image.nix). 0 heisst laut Modul-Kommentar "disable timeout" --
  # damit bootet der Stick sofort durch, ohne dass ein Menue erscheint.
  boot.loader.timeout = lib.mkForce 0;

  # Der Eintrag heisst dann schlicht "NixOS" statt
  # "NixOS 26.05.xxxx (Installer)".
  system.nixos.label = lib.mkForce "";
  isoImage.appendToMenuLabel = lib.mkForce "";
  isoImage.prependToMenuLabel = lib.mkForce "";

  # ── Tastatur ──────────────────────────────────────────────────────────────
  # de-latin1, nicht "de": nur damit liegen Umlaute und '#' richtig --
  # letzteres braucht man fuer das Passwort.
  console.keyMap = "de-latin1";
  services.xserver.xkb.layout = "de";
  i18n.defaultLocale = "de_DE.UTF-8";
  time.timeZone = "Europe/Berlin";

  # ── Passwoerter ───────────────────────────────────────────────────────────
  # Das Installer-Profil setzt initialHashedPassword = "". Beide Optionen
  # gleichzeitig loesen eine Praezedenz-Warnung aus; hier eindeutig machen.
  users.users.root = {
    initialHashedPassword = lib.mkForce null;
    password = lib.mkForce livePassword;
    openssh.authorizedKeys.keys = authorizedKeys;
  };
  users.users.nixos = {
    initialHashedPassword = lib.mkForce null;
    password = lib.mkForce livePassword;
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  # ── SSH laeuft ab Sekunde eins ────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      # Auf einem Rettungsmedium ist root noetig -- Partitionieren und
      # nixos-install gehen nicht ohne.
      PermitRootLogin = lib.mkForce "yes";
      # Key ist der Normalweg, Passwort die Rueckfallebene an fremder Hardware.
      PasswordAuthentication = lib.mkForce true;
    };
  };

  networking = {
    hostName = "q958-rescue";
    useDHCP = lib.mkDefault true;
    # Live-Medium: die Firewall steht dem Rettungseinsatz nur im Weg.
    firewall.enable = false;
  };

  # Auffindbar ohne IP-Kenntnis.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # ── Werkzeuge ─────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    install-q958 # der eine Befehl

    # Partitionieren / Dateisysteme
    gptfdisk
    parted
    dosfstools
    ntfs3g
    cryptsetup
    e2fsprogs # chattr -- fehlte auf der Standard-ISO

    # Rettung
    ddrescue
    smartmontools
    nvme-cli
    testdisk
    lsof

    # Netz
    curl
    wget
    inetutils
    nmap

    # Arbeiten
    git
    vim
    tmux
    jq
    unzip
    ripgrep # scripts/disko-q958.sh braucht rg
    python3 # fehlte auf der Standard-ISO

    # Komfort
    bat
    eza
    fd
    btop

    # Hardware
    pciutils
    usbutils
  ];

  # ── Was am tty steht ──────────────────────────────────────────────────────
  # \4 wird von agetty durch die IPv4-Adresse ersetzt -- damit steht die
  # Adresse fuer den SSH-Zugriff direkt auf dem Bildschirm.
  services.getty.greetingLine = lib.mkForce "";
  environment.etc."issue".text = lib.mkForce ''

    ================================================================
      q958 RESCUE     Tastatur: de-latin1     SSH: laeuft
    ================================================================

      INSTALLIEREN:   install

      Login hier:     root  /  nixos      Passwort: ${livePassword}
      Von aussen:     ssh root@q958-rescue.local
      IP-Adresse:     \4

    ================================================================

  '';

  # Nach dem Login nochmal dasselbe -- man sieht /etc/issue nicht mehr,
  # sobald man eingeloggt ist.
  users.motd = ''

    INSTALLIEREN:  install          (loescht die interne Platte, fragt vorher)
    Nur pruefen:   lsblk

    Danach:  reboot   ->   ssh jarvis@q958.local
  '';

  # ── ISO-Metadaten ─────────────────────────────────────────────────────────
  image.fileName = lib.mkForce "q958-rescue.iso";
  isoImage = {
    volumeID = lib.mkForce "Q958RESCUE";
    makeUsbBootable = true;
    makeEfiBootable = true;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    max-jobs = "auto";
  };
}
