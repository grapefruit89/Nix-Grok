# ---
# schema: "20xx=Domäne+Position; Port 4180=Upstream-Ausnahme (nicht 2028)"
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
  credStore = config.my.creds.storeDir;
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  ingress = import ../../lib/caddy-ingress.nix { inherit lib caddy; };
  oauthUpstream = "127.0.0.1:${toString config.my.ports.oauth2-proxy}";
in
{
  options.my.services.oauth2-proxy = {
    enable = lib.mkEnableOption "oauth2-proxy OIDC Forward-Auth (Pocket-ID als IdP)";
    clientId = lib.mkOption {
      type = lib.types.str;
      default = "setup-pending";
      description = "OIDC Client ID (Pocket-ID App) — aus profile.local.nix via machines/q958.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.creds.enable;
        message = ''
          oauth2-proxy requires my.creds.enable — client-secret + cookie-secret via systemd-creds.
        '';
      }
    ];

    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      clientID = cfg.clientId;
      clientSecretFile = "${credStore}/oauth2-proxy-client-secret.cred";
      redirectURL = "https://oauth.${domain}/oauth2/callback";
      oidcIssuerUrl = "https://auth.${domain}";
      upstream = "static://202";
      setXauthrequest = true;
      httpAddress = "http://127.0.0.1:${toString config.my.ports.oauth2-proxy}";
      cookie = {
        secretFile = "${credStore}/oauth2-proxy-cookie-secret.cred";
        domain = ".${domain}";
        secure = true;
      };
      email.domains = [ "*" ];
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1" ];
      extraConfig = {
        "skip-provider-button" = "true";
      };
    };

    services.caddy.virtualHosts."oauth.${domain}" = {
      extraConfig = ingress.genSecurityOnlyVhost oauthUpstream;
    }
    // lib.optionalAttrs config.my.security.acme.enable {
      useACMEHost = domain;
    };

    systemd.services.oauth2-proxy = {
      serviceConfig = {
        LoadCredential = lib.mkForce [ ];
        LoadCredentialEncrypted = [
          "client-secret:${credStore}/oauth2-proxy-client-secret.cred"
          "cookie-secret:${credStore}/oauth2-proxy-cookie-secret.cred"
        ];
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
