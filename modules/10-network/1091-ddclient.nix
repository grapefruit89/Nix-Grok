# ---
# schema: "109x=Infrastruktur-Band (kein Service-Port)"
# meta:
#   layer: 3
#   role: module
#   purpose: Dual-Agent Local (LAN) & External (WAN) IP Sync to Cloudflare via ddclient
#   tags:
#     - dns
#     - network
#     - cloudflare
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = config.my.configs.identity.domain;
  credStore = config.my.creds.storeDir;
in
{
  options.my.services.ddclient = {
    enable = lib.mkEnableOption "Cloudflare Dual-Agent IP Sync via ddclient";
  };

  config = lib.mkIf config.my.services.ddclient.enable {
    assertions = [
      {
        assertion = config.my.creds.enable;
        message = "ddclient requires my.creds.enable — CF_DDNS_API_TOKEN via systemd-creds.";
      }
    ];

    services.ddclient = {
      enable = true;
      
      # We define global auth credentials here. 
      # The NixOS module automatically puts these at the top of the config file.
      protocol = "cloudflare";
      zone = domain;
      username = "token"; # Standard dummy username for Cloudflare API tokens
      passwordFile = "/run/credentials/ddclient.service/CF_DDNS_API_TOKEN";
      interval = "5m";

      # We intentionally do NOT use the global `usev4` or `domains` options here.
      # Instead, we define two separate jobs in extraConfig to sync both LAN and WAN.
      
      extraConfig = ''
        # ==========================================
        # JOB 1: EXTERNAL WAN IP (The "Clean Polling")
        # ==========================================
        # Asks Cloudflare's trace endpoint for our true public IP and updates
        # the specific subdomains that must be exposed to the internet.
        use=web, web=cloudflare
        jellyfin.${domain}, audiobookshelf.${domain}, navidrome.${domain}

        # ==========================================
        # JOB 2: INTERNAL LAN IP (The "iproute2 Hack")
        # ==========================================
        # Asks the Linux kernel for the active local IP (e.g. 192.168.x.x) and updates
        # the root domain and the wildcard domain for internal resolution.
        use=cmd, cmd='${pkgs.iproute2}/bin/ip route get 1.1.1.1 | ${pkgs.gnused}/bin/sed -n "s/.*src \([0-9.]*\).*/\1/p"'
        *.${domain}, @
      '';
    };

    systemd.services.ddclient = {
      serviceConfig = {
        # Load the encrypted Cloudflare API token via systemd-creds
        LoadCredentialEncrypted = "CF_DDNS_API_TOKEN:${credStore}/CF_DDNS_API_TOKEN.cred";
      };
      after = [
        "q958-secrets-provision.service"
        "credential-store-check.service"
      ];
      wants = [
        "q958-secrets-provision.service"
        "credential-store-check.service"
      ];
    };
  };
}
