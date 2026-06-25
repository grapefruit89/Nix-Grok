# ---
# meta:
#   layer: 4
#   role: user
#   purpose: System-User moritz aus profile.nix
#   tags:
#     - user
#     - moritz
# ---
{ config, pkgs, ... }:

let
  u = import ./profile.nix;
in
{
  imports = [ ./preferences.nix ];

  users.users.${u.name} = {
    isNormalUser = true;
    description = u.description;
    extraGroups = u.extraGroups;
    shell = pkgs.${u.shell};
    openssh.authorizedKeys.keys = u.authorizedKeys;

    # hashedPasswordFile = config.sops.secrets."users/moritz/password".path;
  };
}