# ---
# meta:
#   layer: 4
#   role: user
#   purpose: System-User moritz — parallel zu admin, gleiche Rechte
#   tags:
#     - user
#     - moritz
# ---
{ pkgs, ... }:
let
  u = import ./profile.nix;
in
{
  imports = [ ./preferences.nix ];

  users.users.${u.name} = {
    isNormalUser = true;
    inherit (u) description;
    inherit (u) extraGroups;
    shell = pkgs.${u.shell};
    openssh.authorizedKeys.keys = u.authorizedKeys;
  };
}
