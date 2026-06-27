# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Paperless-ngx Dokumentenarchiv
#   docs:
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - paperless-web
#   tags:
#     - automation
# ---
{
  config,
  lib,
  ...
}:
let
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  cfgPaperless = config.my.services.paperless;
  domain = config.my.configs.identity.domain;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfgPaperless.enable {
      services.paperless = {
        enable = true;
        address = "127.0.0.1";
        inherit (cfgPaperless) port;
        inherit (cfgPaperless) dataDir;
        inherit (cfgPaperless) consumptionDir;
        settings = {
          PAPERLESS_URL = "https://paperless.${domain}";
          PAPERLESS_ALLOWED_HOSTS = "localhost,127.0.0.1,paperless.${domain}";
          PAPERLESS_TIME_ZONE = "Europe/Berlin";
          PAPERLESS_OCR_LANGUAGE = "deu+eng";
          PAPERLESS_OCR_MODE = "redo";
          PAPERLESS_OCR_OUTPUT_TYPE = "pdfa";
          PAPERLESS_TASK_WORKERS = "2";
          PAPERLESS_THREADS_PER_WORKER = "2";
        };
      };

      systemd.slices.system-paperless.sliceConfig = memory.paperless.slice;

      systemd.services.paperless-web.serviceConfig = lib.mkMerge [
        memory.paperless.service
        {
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ReadWritePaths = [
            cfgPaperless.dataDir
            cfgPaperless.consumptionDir
          ];
          CapabilityBoundingSet = "";
          RestrictNamespaces = true;
          ProtectClock = true;
          ProtectHostname = true;
          LockPersonality = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        }
      ];

      systemd.services.paperless-scheduler.serviceConfig = memory.paperless.service;

      systemd.services.paperless-task-queue.serviceConfig = memory.paperless.service;

      my.impermanence.extraPaths = [
        cfgPaperless.dataDir
        cfgPaperless.consumptionDir
      ];
    })
  ];
}
