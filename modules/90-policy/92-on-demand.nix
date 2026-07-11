# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Policy — systemd socket on-demand für selten genutzte HTTP-Apps
#   docs:
#     - docs/adr/5033-systemd-socket-on-demand.md
#   tags:
#     - policy
#     - on-demand
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.policy.onDemand;
in
{
  options.my.policy.onDemand = {
    enable = lib.mkEnableOption ''
      On-demand HTTP via systemd socket-proxyd (kein Sablier, kein Docker).
      Selten genutzte Apps starten erst bei erstem TCP-Connect auf den Public-Port.
    '';

    internalOffset = lib.mkOption {
      type = lib.types.int;
      default = 10000;
      description = ''
        Backend-Port = Public-Port + Offset. Caddy/Gatus bleiben auf Public-Port.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.internalOffset >= 1000;
        message = "my.policy.onDemand.internalOffset muss >= 1000 sein (Port-Kollisionen vermeiden).";
      }
    ];
  };
}
