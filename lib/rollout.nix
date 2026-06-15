# Gemeinsame Rollout-Helfer — keine Host-/User-Werte.
{ lib, stufe }:

let
  erstAb =
    minStufe:
    if stufe < minStufe then lib.mkForce false else lib.mkForce true;
in
{
  inherit erstAb;
}