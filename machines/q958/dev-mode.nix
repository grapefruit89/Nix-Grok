# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: nixos-rebuild Dev-Mode-Warnung für Platzhalter-Secrets
#   tags:
#     - dev
#     - secrets
# ---
{
  config,
  lib,
  ...
}: let
  p = import ./profile.nix;
  devLib = import ../../lib/dev-secrets.nix {
    inherit lib;
    secretsDir = p.secrets.dir;
    devKeys = p.secrets.devKeys;
    files = p.secrets.files;
  };
in {
  warnings = [
    (devLib.mkWarning {
      rolloutStufe = p.rollout.stufe;
      mode = config.my.mode;
    })
  ];
}
