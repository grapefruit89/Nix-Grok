# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Let's Encrypt DNS-01 Wildcard-Cert via Cloudflare — security.acme
#   tags:
#     - acme
#     - tls
#     - caddy
# ---
{
  config,
  lib,
  ...
}:
let
  domain = config.my.configs.identity.domain;
  cfg = config.my.security.acme;
  credStore = config.my.creds.storeDir;
in
{
  options.my.security.acme = {
    enable = lib.mkEnableOption "Let's Encrypt DNS-01 Wildcard-Cert via Cloudflare";
    email = lib.mkOption {
      type = lib.types.str;
      description = "E-Mail für Let's Encrypt-Benachrichtigungen.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.creds.enable;
        message = "ACME requires my.creds.enable — CF_DNS_API_TOKEN via systemd-creds.";
      }
    ];

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
      certs."${domain}" = {
        domain = "*.${domain}";
        dnsProvider = "cloudflare";
        group = "caddy";
        dnsResolver = "127.0.0.53:53";
        extraLegoFlags = [
          "--dns.propagation-wait"
          "60s"
        ];
        credentialFiles = {
          CF_DNS_API_TOKEN_FILE = "${credStore}/CF_DNS_API_TOKEN_FILE.cred";
        };
      };
    };

    systemd.services."acme-${domain}" = {
      serviceConfig = {
        LoadCredential = lib.mkForce [ ];
        LoadCredentialEncrypted = "CF_DNS_API_TOKEN_FILE:${credStore}/CF_DNS_API_TOKEN_FILE.cred";
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
