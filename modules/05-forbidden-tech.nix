# ---
# meta:
#   id: NIXH-05-MOD-003
#   layer: 3
#   role: module
#   purpose: Forbidden-technology Build-time Assertions
#   lib:
#     - lib/forbidden-tech.nix
#   tags:
#     - policy
# ---
{ config, lib, ... }:

let
  policy = import ../lib/forbidden-tech.nix { inherit lib; };
in
{
  options.my.policy.forbidden-tech = {
    enable = lib.mkEnableOption "Forbidden-technology assertions (Docker, Cron, …)";
  };

  config = {
    my.policy.forbidden-tech.enable = lib.mkDefault true;

    assertions = lib.optionals config.my.policy.forbidden-tech.enable (
      policy.baselineAssertions config
      ++ lib.optionals (config.my.security.firewall.enable or false) (policy.firewallAssertions config)
    );
  };
}
