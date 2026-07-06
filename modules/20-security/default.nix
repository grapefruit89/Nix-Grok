{ ... }:
{
  imports = [
    ./15-firewall.nix
    ./20-security.nix
    ./21-sovereign-unlock.nix
    ./22-fail2ban.nix
    ./23-acme.nix
    ./25-kernel-policy.nix
    ./26-kernel-hardening.nix
    ./27-hardened-core.nix
    ./28-oauth2-proxy.nix
    ./29-secrets-portal.nix
  ];
}
