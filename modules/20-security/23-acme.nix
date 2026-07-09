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
        # CF_DNS_API_TOKEN + CF_PROPAGATION_TIMEOUT — provisioniert durch secrets.nix
        environmentFile = "/var/lib/secrets/cloudflare_acme_env";
        group = "caddy";
        # 127.0.0.53 (systemd-resolved, Loopback) für CF-Apex-Domain-Bestimmung.
        # Blocky hört nur auf LAN-IP 192.168.2.73 → Firewall blockiert UDP 53
        # auf non-loopback. Auth-NS direkt (CF) ist ebenfalls geblockt.
        # propagation-wait=60s: kein DNS-Check, nur statisches Warten.
        # CF's interne Replikation zur auth-NS dauert <5s — 60s ist safe.
        dnsResolver = "127.0.0.53:53";
        extraLegoFlags = [
          "--dns.propagation-wait"
          "60s"
        ];
      };
    };
  };
}
