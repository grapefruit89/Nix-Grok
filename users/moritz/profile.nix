# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Einzige Datenquelle aller Moritz-User-Werte — erbt von admin, name=moritz
#   tags:
#     - profile
#     - user
# ---
let
  adminProfile = import ../admin/profile.nix;
in
adminProfile
// {
  name = "moritz";
  description = "moritz";
}
