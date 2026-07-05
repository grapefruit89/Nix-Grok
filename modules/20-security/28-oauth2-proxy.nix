# ---
# meta:
#   layer: 3
#   role: module
#   purpose: oauth2-proxy OIDC Forward-Auth — SSO für Dienste ohne natives OIDC
#   tags:
#     - sso
#     - oauth2-proxy
#     - caddy
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.oauth2-proxy;
  domain = config.my.configs.identity.domain;
in
{
  options.my.services.oauth2-proxy = {
    enable = lib.mkEnableOption "oauth2-proxy OIDC Forward-Auth (Pocket-ID als IdP)";
  };

  config = lib.mkIf cfg.enable {
    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      # Wird durch OAUTH2_PROXY_CLIENT_ID in keyFile überschrieben (secrets.nix aus profile.local.nix)
      clientID = "placeholder";
      keyFile = "/var/lib/secrets/oauth2-proxy.env";
      redirectURL = "https://oauth.${domain}/oauth2/callback";
      cookie = {
        secretFile = "/var/lib/secrets/oauth2-proxy-cookie-secret";
        domain = ".${domain}";
        secure = true;
      };
      email.domains = [ "*" ];
      reverseProxy = true;
      extraConfig = {
        oidc_issuer_url = "https://auth.${domain}";
        skip_provider_button = "true";
        set_xauthrequest = "true";
        # Auth-only Modus: Caddy übernimmt das eigentliche Proxying
        upstreams = "static://202";
        http_address = "127.0.0.1:4180";
      };
    };

    # Öffentlicher Caddy-Endpunkt für Login/Callback-Flow und Sign-in-Redirects
    services.caddy.virtualHosts."oauth.${domain}" = {
      extraConfig = "reverse_proxy 127.0.0.1:4180";
    }
    // lib.optionalAttrs config.my.security.acme.enable {
      useACMEHost = domain;
    };

    # Startet erst nach Secrets-Provisioning (keyFile + cookie.secretFile müssen existieren)
    systemd.services.oauth2-proxy = {
      after = [ "q958-secrets-provision.service" ];
      wants = [ "q958-secrets-provision.service" ];
    };
  };
}
