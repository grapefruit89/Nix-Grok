# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Jellyfin QuickSync + Jellyseerr hinter Caddy
#   docs:
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - jellyfin
#     - seerr
#   tags:
#     - media
#     - jellyfin
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  cfgJellyfin = config.my.services.jellyfin;
  cfgJellyseerr = config.my.services.jellyseerr;
  domain = config.my.configs.identity.domain;
  dnsMap = import ../../lib/dns-map.nix { inherit domain; };
  portJellyfin = config.my.ports.jellyfin;
  portJellyseerr = config.my.ports.jellyseerr;
  locale = config.my.configs.locale;
  localeLang = locale.language or "de";
  localeUi = lib.replaceStrings [ "_" ] [ "-" ] (locale.default or "de_DE.UTF-8");
  localeCc = lib.toUpper (lib.substring 3 2 localeUi);
  jellyfinUrl = "https://${dnsMap.host "jellyfin"}";

  jellyfinConfigSeeds = pkgs.runCommand "jellyfin-config-seeds" { } ''
    mkdir -p $out
    ${pkgs.gnused}/bin/sed \
      -e 's|@LOCALE_LANG@|${localeLang}|g' \
      -e 's|@LOCALE_CC@|${localeCc}|g' \
      -e 's|@LOCALE_UI@|${localeUi}|g' \
      ${./data/jellyfin-system.xml} > $out/system.xml
    ${pkgs.gnused}/bin/sed \
      -e 's|@JELLYFIN_URL@|${jellyfinUrl}|g' \
      ${./data/jellyfin-network.xml} > $out/network.xml
  '';

in
{
  config = lib.mkMerge [
    (lib.mkIf cfgJellyfin.enable (
      lib.mkMerge [
        {
          services.jellyfin = {
            enable = true;
            openFirewall = false;
          };

          systemd.services.jellyfin.preStart = lib.mkBefore ''
            install -d -m 0750 -o jellyfin -g jellyfin /var/lib/jellyfin/config
            for seed in system.xml network.xml; do
              if [ ! -f "/var/lib/jellyfin/config/$seed" ]; then
                install -m 0640 -o jellyfin -g jellyfin \
                  ${jellyfinConfigSeeds}/$seed /var/lib/jellyfin/config/$seed
              fi
            done
          '';

          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              intel-media-driver
              intel-compute-runtime
              ocl-icd
            ];
          };

          users.users.jellyfin.extraGroups = [
            "video"
            "render"
            "media"
          ];

          systemd.services.jellyfin.environment = {
            LIBVA_DRIVER_NAME = "iHD";
            LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
            VDPAU_DRIVER = "va_gl";
            OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
          };

          environment.systemPackages = with pkgs; [
            libva-utils
            intel-gpu-tools
          ];

        }
        (factory.mkStreamer {
          inherit config;
          name = "jellyfin";
          port = portJellyfin;
          useGPU = true;
          manageIngress = false;
          memoryPolicy = memory.jellyfin { };
          persistDirs = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
          ];
          readWritePaths = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
            "/run/jellyfin-transcode"
            "/mnt/fast_pool/cache/jellyfin"
            "/mnt/fast_pool/metadata/jellyfin"
            "/data/downloads"
          ];
          readOnlyPaths = [
            "/data/media"
            "${pkgs.intel-media-driver}/lib"
            "${pkgs.intel-compute-runtime}/lib"
            "/run/opengl-driver"
          ];
          extraSystemd = {
            IPAddressAllow = lib.mkForce [
              "127.0.0.0/8"
              "10.0.0.0/8"
              "192.168.0.0/16"
              "100.64.0.0/10"
            ];
            IPAddressDeny = lib.mkForce "any";
          };
        })
      ]
    ))

    (lib.mkIf cfgJellyseerr.enable (
      lib.mkMerge [
        {
          services.seerr = {
            enable = true;
            port = portJellyseerr;
            openFirewall = false;
          };
        }
        (factory.mkService {
          inherit config;
          name = "seerr";
          port = portJellyseerr;
          mode = "sso";
          persistDirs = [ "/var/lib/seerr" ];
          readWritePaths = [ "/var/lib/seerr" ];
        })
      ]
    ))
  ];
}
