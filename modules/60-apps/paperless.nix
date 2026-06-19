{ config, lib, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgPaperless = config.my.services.paperless;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgPaperless.enable {
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
        PAPERLESS_OCR_LANGUAGE = "deu";
        PAPERLESS_OCR_MODE = "skip";
        PAPERLESS_OCR_CLEAN = "clean";
        PAPERLESS_OCR_OUTPUT_TYPE = "pdfa";
        PAPERLESS_REDIS = "unix:///run/redis-valkey/valkey.sock";
        PAPERLESS_TASK_WORKERS = "2";
        PAPERLESS_THREADS_PER_WORKER = "2";
      };
    };

    users.users.paperless.extraGroups = [ "redis" ];

    systemd.services.paperless-web.serviceConfig = {
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ReadWritePaths = [ cfgPaperless.dataDir cfgPaperless.consumptionDir ];
      CapabilityBoundingSet = "";
      RestrictNamespaces = true;
      ProtectClock = true;
      ProtectHostname = true;
      LockPersonality = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };

    services.caddy.virtualHosts."paperless.${domain}" = {
      extraConfig = caddy.proxySso cfgPaperless.port;
    };
  };
}
