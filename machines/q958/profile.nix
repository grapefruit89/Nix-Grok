# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Einzige Datenquelle aller q958-Maschinenwerte
#   docs:
#     - docs/ROADMAP.md
#   tags:
#     - profile
#     - single-source-of-truth
# ---
let
  localPath =
    if builtins.pathExists ./profile.local.nix then ./profile.local.nix
    else if builtins.pathExists /etc/nixos/machines/q958/profile.local.nix
    then /etc/nixos/machines/q958/profile.local.nix
    else null;
  local =
    if localPath != null then
      import localPath
    else
      throw "profile.local.nix fehlt — cp machines/q958/profile.local.nix.example machines/q958/profile.local.nix";
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
    menuName = "Basics_erfolgreich";
    sortKey = "0_basis";
    # 8 rollierende NixOS-Generationen + 2 feste Baselines (boot-baseline.nix) ≈ 10 Menü-Einträge
    generationLimit = 8;
    pinnedGenerations = [ 85 86 ];
    kernelParams = [ "i915.enable_guc=2" ];
  };

  network = {
    lan = {
      ip = "192.168.2.73";
      prefixLength = 24;
      interface = "eno1";
      gateway = "192.168.2.1";
      dns = [ "127.0.0.1" ];
      systemdNetworkName = "10-lan";
    };
    tailscaleIP = "100.64.0.1";
    sshPort = 22;
    productionSshPort = 53844;
    blocky = {
      upstream = [
        "tcp-tls:1.1.1.1:853" # Cloudflare
        "tcp-tls:1.0.0.1:853"
        "tcp-tls:9.9.9.9:853" # Quad9
        "tcp-tls:149.112.112.112:853"
        "tcp-tls:194.242.2.2:853" # Mullvad
        "tcp-tls:dnsforge.de:853"
      ];
    };
    privado = {
      endpoint = "91.148.245.70:51820";
      publicKey = "KgTUh3KLijVluDvNpzDCJJfrJ7EyLzYLmdHCksG4sRg=";
      address = "100.64.8.117/32";
      dns = [ "198.18.0.1" "198.18.0.2" ];
    };
    dns = {
      bootstrap = [
        "tcp-tls:1.1.1.1:853"
        "tcp-tls:9.9.9.9:853"
      ];
    };
    # IPv6 Homelab: ad acta — nur v4 auf LAN-PHY (eno1). Ausnahme: tailscale0 (Mesh).
    ipv6 = {
      disableOnInterfaces = [ "eno1" ];
      firewall = false;
    };
    ddns = {
      zone = "m7c5.de";
      record = "nix";
      enable = ((local.secrets.cloudflare or { }).apiToken or "") != "";
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

    # Stufe 9 (Impermanence): NIXPERSIST mount — getrennt von hardware.nix "/" (Stufe 0–8)
    impermanence = {
      mountPoint = "/persist";
    };
  };

  secrets = {
    dir = "/var/lib/secrets";
    files = {
      tailscaleToken = "tailscale_token";
      pocketId = "pocket-id.env";
      context7 = "context7.env";
      privadoKey = "privado_private_key";
      privadoEnv = "privado.env";
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
    stufe = 8;
  };

  # i3-9100: 4 Kerne, 32 GB — 4 parallele Jobs, je 1 Kern (volle CPU, kein idle-daemon)
  nix = {
    maxJobs = 4;
    cores = 1;
    daemonLowPriority = false;
  };

  iot = {
    zigbeeCoordinator = {
      host = "192.168.1.100";
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
    firewall = {
      lanCidrs = [ "192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12" ];
      blockedCountries = [ "cn" "ru" "kp" "ir" "sy" "vn" ];
      allowLanDns = true;
      tailscaleNotrack = true;
    };
  };

  alerting = {
    ntfyTopic = local.alerting.ntfyTopic or "";
    webhookUrl = local.alerting.webhookUrl or "";
  };

  restic = {
    healthcheckUrl = local.restic.healthcheckUrl or "";
    offsiteEnable =
      let repo = (local.secrets.restic or { }).repository or "";
      in repo != "";
  };

  kernel = let
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
  in {
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