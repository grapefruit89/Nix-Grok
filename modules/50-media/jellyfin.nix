{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgJellyfin = config.my.services.jellyfin;
  cfgJellyseerr = config.my.services.jellyseerr;
  domain = config.my.configs.identity.domain;
  portJellyfin = config.my.ports.jellyfin;
  portJellyseerr = config.my.ports.jellyseerr;

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgJellyfin.enable {
      services.jellyfin = {
        enable = true;
        openFirewall = false;
      };

      # System-wide graphics pipeline and compute runtime for tone mapping
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-compute-runtime
          ocl-icd
        ];
      };

      # DRI-Zugriffsgruppe für die Intel UHD 630 GPU hinzufügen
      users.users.jellyfin.extraGroups = [ "video" "render" "media" ];

      # Intel Media-Treiber und OpenCL-Laufzeitumgebung für VA-API/QuickSync
      systemd.services.jellyfin.environment = {
        LIBVA_DRIVER_NAME = "iHD";
        LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
        VDPAU_DRIVER = "va_gl";
        OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
      };

      # Systemd Sandboxing Härtung
      systemd.services.jellyfin.serviceConfig = {
        MemoryHigh = "4G";
        MemoryMax = "6G";
        OOMScoreAdjust = 100; # Etwas geschützter als der Download-Stack, um Ruckler zu vermeiden

        PrivateDevices = lib.mkForce false; # Erforderlich für DRI-Gerätezugriff
        DeviceAllow = [
          "/dev/dri rw"
          "/dev/dri/card0 rw"
          "/dev/dri/renderD128 rw"
        ];

        # Sandboxing
        NoNewPrivileges = lib.mkForce true;
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        ProtectKernelTunables = lib.mkForce true;
        ProtectKernelModules = lib.mkForce true;
        ProtectControlGroups = lib.mkForce true;
        RestrictRealtime = lib.mkForce false; # Audio/Video benötigt Echtzeit-Puffer
        RestrictSUIDSGID = lib.mkForce true;
        LockPersonality = lib.mkForce true;
        CapabilityBoundingSet = lib.mkForce "";
        UMask = lib.mkForce "0002"; # Prevents permission drift on imported files

        # RAM-backed transcoding directory (SSD Longevity)
        RuntimeDirectory = "jellyfin-transcode";
        RuntimeDirectoryMode = "0700";

        # Dateipfade beschränken
        ReadWritePaths = [
          "/data/state/jellyfin"
          "/var/cache/jellyfin"
          "/run/jellyfin-transcode"
          "/mnt/fast_pool/cache/jellyfin"
          "/mnt/fast_pool/metadata/jellyfin"
          "/data/media"
          "/data/downloads"
        ];
        ReadOnlyPaths = [
          "${pkgs.intel-media-driver}/lib"
          "${pkgs.intel-media-driver}/lib"
          "${pkgs.intel-compute-runtime}/lib"
          "/run/opengl-driver"
        ];

        # Netzwerk-Einschränkung (verhindert unkontrollierten Egress)
        IPAddressAllow = [ "127.0.0.0/8" "10.0.0.0/8" "192.168.0.0/16" "100.64.0.0/10" ];
        IPAddressDeny = "any";

        ExecStart = lib.mkForce "${pkgs.jellyfin}/bin/jellyfin --datadir /data/state/jellyfin --cachedir /var/cache/jellyfin --host 127.0.0.1";
      };

      # Diagnosewerkzeuge systemweit
      environment.systemPackages = with pkgs; [
        libva-utils # vainfo
        intel-gpu-tools # intel_gpu_top
      ];

      # Client-Split: Jellyfin-Apps senden X-Emby-Authorization (MediaBrowser Client=…).
      # Browser (kein Emby-Header beim ersten Load) → Pocket-ID forward_auth.
      # WAN-Schutz zusätzlich: nftables Geo (Stufe 8).
      services.caddy.virtualHosts."jellyfin.${domain}" = {
        extraConfig = ''
          import streamer_headers
          import security_headers

          @jellyfin_client header_regexp X-Emby-Authorization (?i)MediaBrowser

          handle @jellyfin_client {
            ${caddy.streamingBackend portJellyfin}
          }

          handle {
            import sso_auth
            ${caddy.streamingBackend portJellyfin}
          }
        '';
      };
    })

    (lib.mkIf cfgJellyseerr.enable {
      services.seerr = {
        enable = true;
        port = portJellyseerr;
        openFirewall = false;
      };

      # Systemd Sandboxing Härtung
      systemd.services.seerr.serviceConfig = {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        ReadWritePaths = [ "/data/state/seerr" ];
      };
      systemd.services.seerr.environment = {
        HOST = "127.0.0.1";
      };

      services.caddy.virtualHosts."seerr.${domain}" = {
        extraConfig = caddy.proxySsoBypassApp portJellyseerr;
      };
    })
  ];
}

