# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Home-Manager für moritz — importiert admin/home.nix, fixiert username
#   tags:
#     - home-manager
#     - moritz
# ---
{ lib, ... }:
let
  u = import ./profile.nix;
in
{
  imports = [ ../admin/home.nix ];

  home.username = lib.mkForce u.name;
  home.homeDirectory = lib.mkForce "/home/${u.name}";
}
