# Einzige Quelle für alle q958-Maschinenwerte. Keine User-Daten — die liegen unter users/.
# Secrets + Notfall-Passwort: machines/q958/profile.local.nix (gitignored)
let
  local =
    if builtins.pathExists ./profile.local.nix then
      import ./profile.local.nix
    else
      builtins.trace
        "WARNUNG: profile.local.nix fehlt — cp profile.local.nix.example profile.local.nix"
        {
          access.emergency = { };
          secrets.devKeys = { };
        };
in
{
  meta = {
    machine = "q958";
    model = "Fujitsu Esprimo Q958";
    role = "homelab-server";
  };

  system = {
    hostName = "q958";
    stateVersion = "26.05";
  };

  boot = {
    menuName = "Basis-System";
    sortKey = "0_basis";
    generationLimit = 5;
    kernelParams = [ "i915.enable_guc=2" ];
  };

  network = {
    lan = {
      ip = "192.168.2.73";
      prefixLength = 24;
      interface = "eno1";
      gateway = "192.168.2.1";
      dns = [ "127.0.0.1" "1.1.1.1" ];
      systemdNetworkName = "10-lan";
    };
    tailscaleIP = "100.64.0.1";
    sshPort = 22;
    blocky = {
      upstream = [ "1.1.1.1" "8.8.8.8" ];
    };
    dns = {
      doh = [ "https://dns.cloudflare.com/dns-query" ];
      bootstrap = [ "1.1.1.1" ];
      fallback = [ "1.1.1.1" ];
    };
  };

  # Maschinen-Zugang (Notfall) — kein users/-Eintrag, nur bis Homelab steht
  access = {
    emergency = {
      name = "nixos";
      description = "Admin-Zugang (Notfall-Login)";
      passwordHash = local.access.emergency.passwordHash or (
        throw "access.emergency.passwordHash in machines/q958/profile.local.nix setzen"
      );
      extraGroups = [ "wheel" "networkmanager" ];
    };
  };

  hardware = {
    ramGB = 32;
    cpu = {
      model = "i3-9100";
      generation = 9;
      codename = "coffee-lake-s";
      minAllowedGeneration = 7;
    };
    chipset = "Q370";
    gpu = "UHD 630";
    nic = "I219-LM";
    kvmModule = "kvm-intel";
    initrdModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  };

  storage = {
    # q958 Einzelplatte: SATA-SSD = gesamtes Tier A (State). v5 uuid-map sieht sda als Tier B —
    # hier bewusst abweichend, weil nur eine interne SSD existiert.
    singleDisk = true;

    # A/B = kein spinning device. A = NVMe, oder SATA wenn keine NVMe (q958).
    # B = immer SATA-SSD. C = HDD only (cold storage).
    tierPolicy = {
      a = { medium = "ssd"; bus = [ "nvme" "ata" ]; };
      b = { medium = "ssd"; bus = [ "ata" ]; };
      c = { medium = "hdd"; bus = [ "ata" ]; };
    };

    systemLabels = [
      "NIXBOOT"
      "BOOT"
      "NIXPERSIST"
      "NIXHOME_PERSIST"
      "NIXSTORE"
      "CRYPTROOT"
    ];

    tierA = {
      device = "/dev/sda";
      bus = "sata";
      boot = {
        label = "NIXBOOT";
        fsType = "vfat";
        fmask = "0022";
        dmask = "0022";
      };
      persist = {
        label = "NIXPERSIST";
        fsType = "ext4";
        mountPoint = "/";
        disk = "/dev/disk/by-label/NIXPERSIST";
      };
    };

    tierB = {
      label = "NIXDATA";
      bus = "sata";
      legacyPrefixes = [ "TIER_B_" ];
      mountPoint = "/mnt/fast_pool";
      enabled = false;
    };

    tierC = {
      labels = [ "NIXMEDIA" "NIXBACKUP" ];
      legacyPrefixes = [ "TIER_C_" "DISK_STORAGE_" ];
      mountPoint = "/mnt/media";
      enabled = false;
    };

    luks = {
      device = "";
    };

    mediaPoolMountPoint = "/mnt/media";
    fastPoolMountPoint = "/mnt/fast_pool";
    mergerfsEnable = false;
  };

  secrets = {
    dir = "/var/lib/secrets";
    files = {
      tailscaleToken = "tailscale_token";
      pocketId = "pocket-id.env";
      context7 = "context7.env";
      privadoKey = "privado_private_key";
    };

    # Dev-Platzhalter: machines/q958/profile.local.nix (gitignored, rollout.stufe < 9)
    devKeys = local.secrets.devKeys or (
      throw "secrets.devKeys in machines/q958/profile.local.nix setzen"
    );
  };

  integrations = {
    agentZero = {
      url = "http://192.168.2.250:50080";
    };
    amt = {
      host = "192.168.1.100";
      port = 16992;
    };
  };

  rollout = {
    stufe = 5;
  };

  iot = {
    zigbeeCoordinator = {
      host = "slzb-06m.local";
      port = 6638;
    };
    homeAssistant = {
      port = 8123;
    };
    zigbeeStack = {
      mqttPort = 1883;
      zigbeePort = 8075;
      adapter = "ember";
    };
  };

  security = {
    sovereignUnlock = {
      sshPort = 2222;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
      ];
    };
  };

  restic = {
    healthcheckUrl = "https://hc-ping.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
  };

  kernel =
    let
      moduleRoles = {
        e1000e = "Intel I219-LM Onboard-NIC (eno1)";
        i915 = "Intel UHD 630 — Jellyfin VA-API";
        ahci = "SATA-Controller — Tier-A SSD /dev/sda";
        sd_mod = "SCSI-Disk-Treiber — Systemplatte";
        libata = "ATA-Library — SATA";
        scsi_mod = "SCSI-Core";
        xhci_pci = "USB 3.0 — Tastatur, Install-Stick";
        usb_storage = "USB-Mass-Storage";
        usbhid = "USB-HID";
        hid = "HID-Core";
        kvm = "KVM-Virtualisierung";
        kvm_intel = "KVM Intel (i3-9100)";
        zram = "ZRAM-Swap";
        mei_me = "Intel ME Interface — Q370 PCH";
        intel_pch_thermal = "Intel PCH-Thermal — Q370";
      };
    in
    {
      # Zwiebelschale: lib/kernel/* = Schicht A+B, hier nur Schicht C (Host)
      policy = {
        mode = "homelab-strict";
        homelabProfile = "headless-server";
      };

      inherit moduleRoles;
      requiredModules = builtins.attrNames moduleRoles;

      requiredInitrdModules = [
        "xhci_pci"
        "ahci"
        "usb_storage"
        "sd_mod"
      ];

      # Module außerhalb der Homelab-Whitelist, die dieser Host trotzdem braucht
      whitelistExtra = [ ];

      # Schicht C — Host-Blacklist (zusätzlich zu A+B)
      blacklist = { };
    };
}
