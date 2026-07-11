# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Blocky-Allowlist — Pfad + tmpfiles-Regel atomar (kein Drift zwischen Option und tmpfiles)
#   tags:
#     - blocky
#     - dns
# ---
{ user }:
let
  path = "/home/${user.name}/blocky-allowlist.txt";
in
{
  file = path;
  tmpfilesRule = "f ${path} 0644 ${user.name} users -";
}
