# ---
# domain: "20"
# schema: "20xx = Domäne 20 + Dateiposition; 2029 = UID secrets-portal (ADR-011)"
# ---
{ ... }:
{
  imports = [
    ./2015-firewall.nix
    ./2020-security.nix
    ./2021-sovereign-unlock.nix
    ./2022-fail2ban.nix
    ./2023-acme.nix
    ./2025-kernel-policy.nix
    ./2026-kernel-hardening.nix
    ./2027-hardened-core.nix
    ./2028-oauth2-proxy.nix
    ./2029-secrets-portal.nix
    ./2030-access-policy.nix
  ];
}
