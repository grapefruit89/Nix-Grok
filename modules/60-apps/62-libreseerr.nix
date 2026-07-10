# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Libreseerr — Buch-Anfragen für Readarr (nativ, kein Docker)
#   tags:
#     - apps
#     - libreseerr
#     - readarr
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.libreseerr;
  factory = import ../../lib/service-factory.nix { inherit lib; };
  port = config.my.ports.libreseerr;
  package = pkgs.callPackage ../../packages/libreseerr { };
in
{
  options.my.services.libreseerr = {
    enable = lib.mkEnableOption "Libreseerr book request UI (Readarr companion)";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.libreseerr;
      description = "Libreseerr listen port.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        users.users.libreseerr = {
          isSystemUser = true;
          group = "libreseerr";
          home = "/var/lib/libreseerr";
        };
        users.groups.libreseerr = { };

        systemd.tmpfiles.rules = [
          "d /var/lib/libreseerr 0750 libreseerr libreseerr -"
          "d /var/lib/libreseerr/data 0750 libreseerr libreseerr -"
        ];

        my.impermanence.extraPaths = [ "/var/lib/libreseerr" ];

        systemd.services.libreseerr = {
          description = "Libreseerr — book requests for Readarr";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            LIBRESEERR_BIND = "127.0.0.1:${toString port}";
            DATA_DIR = "/var/lib/libreseerr/data";
          };
          serviceConfig = {
            Type = "simple";
            User = "libreseerr";
            Group = "libreseerr";
            StateDirectory = "libreseerr";
            WorkingDirectory = "/var/lib/libreseerr/data";
            ExecStart = "${package}/bin/libreseerr";
            Restart = "on-failure";
            RestartSec = "10s";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            ReadWritePaths = [ "/var/lib/libreseerr" ];
          };
        };
      }
      (factory.mkService {
        inherit config;
        name = "libreseerr";
        inherit port;
        mode = "sso";
        caddyOnly = true;
        persistDirs = [ "/var/lib/libreseerr" ];
      })
    ]
  );
}
