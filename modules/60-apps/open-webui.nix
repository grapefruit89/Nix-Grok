{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgOpenWebui = config.my.services.open-webui;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgOpenWebui.enable {
    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      inherit (cfgOpenWebui) port;
      environment = {
        OLLAMA_API_BASE_URL = cfgOpenWebui.ollamaUrl;
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";
      };
    };

    services.caddy.virtualHosts."ai.${domain}" = {
      extraConfig = caddy.proxySso cfgOpenWebui.port;
    };

    systemd.services.open-webui.serviceConfig = {
      OOMScoreAdjust = 500;
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      SupplementaryGroups = [ "render" "video" ];
      SystemCallFilter = [ "@system-service" "~@privileged" ];
      OOMScoreAdjust = 200;
    };
  };
}
