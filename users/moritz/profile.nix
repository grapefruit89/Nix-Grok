# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Einzige Datenquelle moritz-spezifischer Werte (Keys, Domain)
#   tags:
#     - profile
#     - moritz
# ---
let
  baseDomain = "m7c5.de";
  # Nix-Subdomain-Präfix — leer lassen ("") um Services direkt unter m7c5.de zu schalten.
  # Solange Unraid nix.m7c5.de nicht belegt: "nix" → services unter service.nix.m7c5.de
  nixSubdomain = "nix";
in
{
  name = "moritz";
  inherit baseDomain nixSubdomain;
  domain = if nixSubdomain != "" then "${nixSubdomain}.${baseDomain}" else baseDomain;
  description = "moritz";
  shell = "bash";
  extraGroups = [
    "networkmanager"
    "wheel"
  ];
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvttE1EzwLJpzFc/LuuXZP485Ma0mEJQiu3iMXaO58W"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
  ];
}
