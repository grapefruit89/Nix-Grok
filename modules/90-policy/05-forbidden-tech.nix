{
  config,
  lib,
  ...
}:
let
  policy = import ../../lib/forbidden-tech.nix { inherit lib; };
in
{
  options.my.policy.forbidden-tech = {
    enable = lib.mkEnableOption "Forbidden-technology assertions (Docker, Cron, …)";
  };

  config = {
    my.policy.forbidden-tech.enable = lib.mkDefault true;

    assertions = lib.optionals config.my.policy.forbidden-tech.enable (
      policy.baselineAssertions config
      ++ policy.formatterAssertions config
      ++ lib.optionals (config.my.security.firewall.enable or false) (policy.firewallAssertions config)
    );
  };
}
