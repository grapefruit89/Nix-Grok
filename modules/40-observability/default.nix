{ ... }:
{
  imports = [
    ./05-alerting.nix
    ./05-runtime-guard.nix
    ./41-gatus.nix
    ./42-logging.nix
    ./43-crowdsec.nix
    ./44-metrics.nix
  ];
}
