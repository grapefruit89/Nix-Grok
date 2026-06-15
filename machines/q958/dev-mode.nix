# Dev-Mode-Hinweis beim nixos-rebuild — informiert, bricht den Build nicht.
{ config, lib, ... }:

let
  p = import ./profile.nix;
  devLib = import ../../lib/dev-secrets.nix {
    inherit lib;
    secretsDir = p.secrets.dir;
    devKeys = p.secrets.devKeys;
    files = p.secrets.files;
  };
in
{
  warnings = [
    (devLib.mkWarning {
      rolloutStufe = p.rollout.stufe;
      mode = config.my.mode;
    })
  ];
}