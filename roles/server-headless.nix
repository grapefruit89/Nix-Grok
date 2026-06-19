{ config, lib, pkgs, ... }:

{
  # Server is strictly headless and production-hardened
  my.mode = lib.mkDefault "production";

  # Import the strict policy enforcer
  imports = [
    ../modules/90-policy.nix
  ];

  # Server MUST have a firewall
  my.security.firewall.enable = lib.mkDefault true;
}
