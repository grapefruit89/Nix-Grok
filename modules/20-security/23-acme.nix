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
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security.acme = {
    enable = lib.mkEnableOption "Let's Encrypt DNS-01 Wildcard-Cert via Cloudflare";
    email = lib.mkOption {
      type = lib.types.str;
      description = "E-Mail für Let's Encrypt-Benachrichtigungen.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
      certs."${domain}" = {
        domain = "*.${domain}";
        dnsProvider = "cloudflare";
        # CF_DNS_API_TOKEN=<token> — provisioniert durch machines/q958/secrets.nix
        environmentFile = "/var/lib/secrets/cloudflare_acme_env";
        group = "caddy";
        # Outbound UDP 53 blockiert (cleartextDnsBlock) — lego kann authoritative NS
        # nicht direkt pollen. LE validiert selbst; Cloudflare propagiert sofort.
        dnsPropagationCheck = false;
      };
    };
  };
}
