/*
---
id: matrix-tuwunel
domain: 60-apps
status: accepted
upstream_repo: "matrix-construct/tuwunel"
---
*/

{ config, lib, pkgs, ... }:

let
  cfgTuwunel = config.my.services.matrix-tuwunel;
  domain = config.my.configs.identity.domain;

in
{
  options.my.services.matrix-tuwunel = {
    enable = lib.mkEnableOption "Tuwunel Matrix Server";
  };

  config = lib.mkIf cfgTuwunel.enable {
    # 1. The Service (Tuwunel)
    services.matrix-tuwunel = {
      enable = true;
      settings = {
        global = {
          server_name = "matrix.${domain}";
          database_path = "/data/state/tuwunel"; # SSoT: Ext4 path
          port = 6167;
          address = "127.0.0.1"; # Bind to localhost for Caddy
          
          # Disable federation entirely for private friends & family use
          allow_federation = false;
        };
      };
    };

    # 2. Reverse Proxy (Caddy) - SSoT TCP Law Fallback
    services.caddy.virtualHosts."matrix.${domain}" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:6167
      '';
    };

    # 3. Storage Persistence
    environment.persistence."${config.my.impermanence.persistMountPoint}" = lib.mkIf config.my.impermanence.enable {
      directories = [
        "/data/state/tuwunel"
      ];
    };
  };
}
