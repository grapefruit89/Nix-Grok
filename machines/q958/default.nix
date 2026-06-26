# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: q958-Verdrahtung — Module-Imports und my.configs ohne .enable
#   tags:
#     - wiring
#     - q958
# ---
{ lib, ... }:

let
  p = import ./profile.nix;
  moritz = import ../../users/moritz/profile.nix;
  zigbeeSocket = "socket://${p.iot.zigbeeCoordinator.host}:${toString p.iot.zigbeeCoordinator.port}";
in
{
  imports = [
    ./hardware.nix
    ../../modules/00-core
    ../../modules/05-storage-policy.nix
    ../../modules/05-forbidden-tech.nix
    ../../modules/05-runtime-guard.nix
    ../../modules/05-alerting.nix
    ../../modules/05-deferred-ops.nix
    ../../modules/25-kernel-policy.nix
    ../../modules/26-kernel-hardening.nix
    ../../modules/27-hardened-core.nix
    ../../modules/10-network.nix
    ../../modules/10-ingress.nix
    ../../modules/10-vpn-confinement.nix
    ../../modules/10-gateway.nix
    ../../modules/15-firewall.nix
    ../../modules/20-security.nix
    ../../modules/30-storage.nix
    ../../modules/35-automount.nix
    ../../modules/36-disk-health.nix
    ../../modules/40-observability.nix
    ../../modules/50-media
    ../../modules/60-apps
    ../../modules/70-forge.nix
    ../../modules/80-gaming.nix
    ../../users/moritz/default.nix
    ./kernel-slim.nix
    ./access.nix
    ./network.nix
    ./storage.nix
    ./secrets.nix
    ./dev-mode.nix
    ./rollout.nix
    ./boot-baseline.nix
    ../../modules/91-security-assertions.nix
    ../../modules/dev/aider.nix
    ../../modules/dev/claude-code.nix
  ];

  nixpkgs.config.allowUnfree = true;
  services.aider.enable = true;
  services.claude-code.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${moritz.name} = import ../../users/moritz/home.nix;
  };

  networking.hostName = p.system.hostName;

  my = {
    core = {
      boot-safeguard.enable = true;
      nix-tuning.enable = true;
      zram-swap.enable = true;
      kernel-slim = {
        enable = true;
        mode = "homelab-strict";
        homelabProfile = "headless-server";
      };
    };

    security.kernel-hardening = {
      enable = true;
      disableIpv6Stack = false;
      hardenTmp = true;
      hardenDevShm = true;
      hardenRunLock = true;
      enableSlubHardening = true;
      panicOnOops = false;
    };

    configs = {
      identity = {
        user = moritz.name;
        domain = moritz.domain;
      };
      hardware = {
        ramGB = p.hardware.ramGB;
      };
      server = {
        lanIP = p.network.lan.ip;
        tailscaleIP = p.network.tailscaleIP;
      };
      storage = {
        tierB.mountPoint = p.storage.fastPoolMountPoint;
        tierC = {
          mountPoint = p.storage.tierC.mountPoint;
          labels = p.storage.tierC.labels;
          legacyPrefixes = p.storage.tierC.legacyPrefixes;
        };
      };
      ddns = {
        zone = p.network.ddns.zone;
        record = p.network.ddns.record;
      };
    };

    ports.ssh = p.network.sshPort;

    services.vpn-confinement = {
      namespaces.usenet = {
        wgConf = "/var/lib/secrets/privado.netns.conf";
        address = p.network.privado.address;
        dns = p.network.privado.dns;
        killSwitch = true;
        healthcheck.endpoint = builtins.elemAt (lib.splitString ":" p.network.privado.endpoint) 0;
        accessibleFrom = [
          "192.168.15.0/24"
          "${p.network.lan.ip}/32"
        ];
        services = [
          "sabnzbd"
          "prowlarr"
        ];
      };
    };

    core.nix-tuning = {
      maxJobs = p.nix.maxJobs;
      cores = p.nix.cores;
      daemonLowPriority = p.nix.daemonLowPriority;
    };

    impermanence = {
      persistentDisk = p.storage.tierA.persist.disk;
      persistMountPoint = p.storage.impermanence.mountPoint;
    };

    alerting = {
      ntfyTopic = p.alerting.ntfyTopic;
      webhookUrl = p.alerting.webhookUrl;
    };

    security = {
      sovereign-unlock = {
        luksDevice = p.storage.luks.device;
        sshPort = p.security.sovereignUnlock.sshPort;
        authorizedKeys = p.security.sovereignUnlock.authorizedKeys;
      };
      firewall = {
        lanCidrs = p.security.firewall.lanCidrs;
        blockedCountries = p.security.firewall.blockedCountries;
        allowLanDns = p.security.firewall.allowLanDns;
        lanInterface = p.network.lan.interface;
        tailscaleNotrack = p.security.firewall.tailscaleNotrack;
      };
    };

    services = {
      storage.poolMountPoint = p.storage.mediaPoolMountPoint;
      storage-mover = {
        sourceDir = "${p.storage.fastPoolMountPoint}/downloads";
        targetDir = "${p.storage.mediaPoolMountPoint}/downloads";
      };
      restic-backup.healthcheckUrl = p.restic.healthcheckUrl;
      homepage.agentZeroUrl = p.integrations.agentZero.url;
      cockpit = {
        amtHost = p.integrations.amt.host;
        amtPort = p.integrations.amt.port;
        exposeAmt = p.integrations.amt.host != "";
      };
      home-assistant = {
        port = p.iot.homeAssistant.port;
        zigbeeDevice = zigbeeSocket;
      };
      zigbee-stack = {
        mqttPort = p.iot.zigbeeStack.mqttPort;
        zigbeePort = p.iot.zigbeeStack.zigbeePort;
        zigbeeDevice = zigbeeSocket;
        adapter = p.iot.zigbeeStack.adapter;
      };
    };
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = p.boot.kernelParams;
  };

  system.stateVersion = p.system.stateVersion;
  services.hermes-agent.enable = true;
}
