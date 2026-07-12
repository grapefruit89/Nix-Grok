# ---
# meta:
#   layer: 4
#   role: user
#   purpose: System-User jarvis — einziger SSH-User, Key-only, wheel
#   tags:
#     - user
#     - jarvis
# ---
{ lib, pkgs, ... }:
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
    hashedPassword = lib.mkForce "!";
    openssh.authorizedKeys.keys = u.authorizedKeys;
  };

  users.users.root = {
    hashedPassword = lib.mkForce "!";
    openssh.authorizedKeys.keys = lib.mkForce [ ];
  };
}
