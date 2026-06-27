# ---
# meta:
#   id: NIXH-50-MED-001
#   layer: 3
#   role: module
#   purpose: Audiobookshelf — Streaming-Caddy, VA-API-ready, RAM-Cap
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/memory_oom.md
#   lib:
#     - lib/service-factory.nix
#     - lib/memory-policy.nix
#   services:
#     - audiobookshelf
#   tags:
#     - media
#     - audiobookshelf
#     - streaming
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.audiobookshelf;
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  port = config.my.ports.audiobookshelf;
  mediaRoot = config.my.services.storage.poolMountPoint;
  storageReady = config.my.services.storage.enable or false;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.audiobookshelf = {
          enable = true;
          host = "127.0.0.1";
          inherit port;
          group = "media";
        };

        users.users.audiobookshelf.extraGroups = lib.mkAfter [
          "media"
          "video"
          "render"
        ];

        hardware.graphics = lib.mkIf cfg.enableQuickSync {
          enable = lib.mkDefault true;
          extraPackages = with pkgs; [
            intel-media-driver
            intel-compute-runtime
          ];
        };
      }

      (factory.mkService {
        inherit config;
        name = "audiobookshelf";
        inherit port;
        mode = "streaming";
        hardeningProfile = "node";
        persistDirs = [ "/var/lib/audiobookshelf" ];
        privateDevices = !cfg.enableQuickSync;
        readWritePaths = [
          "/var/lib/audiobookshelf"
        ]
        ++ lib.optionals storageReady [
          "${mediaRoot}/books"
          "${mediaRoot}/audiobooks"
          "${mediaRoot}/podcasts"
        ];
        memoryPolicy = memory.audiobookshelf { };
        extraSystemd = {
          Restart = lib.mkForce "on-failure";
        }
        // lib.optionalAttrs cfg.enableQuickSync {
          PrivateDevices = lib.mkForce false;
          DeviceAllow = [
            "/dev/dri rw"
            "/dev/dri/card0 rw"
            "/dev/dri/renderD128 rw"
          ];
        };
      })

      (lib.mkIf cfg.enableQuickSync {
        systemd.services.audiobookshelf.environment = {
          LIBVA_DRIVER_NAME = "iHD";
          LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
        };
      })

      (lib.mkIf storageReady {
        systemd.tmpfiles.rules = [
          "d ${mediaRoot}/books 0775 audiobookshelf media -"
          "d ${mediaRoot}/audiobooks 0775 audiobookshelf media -"
          "d ${mediaRoot}/podcasts 0775 audiobookshelf media -"
        ];
      })
    ]
  );
}
