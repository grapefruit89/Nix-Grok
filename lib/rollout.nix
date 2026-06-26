# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Rollout-Helfer erstAb für stufenweise Service-Aktivierung
#   tags:
#     - rollout
# ---
{ lib, stufe }:

let
  erstAb = minStufe: if stufe < minStufe then lib.mkForce false else lib.mkForce true;
in
{
  inherit erstAb;
}
