# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Einzige Datenquelle moritz-spezifischer Werte (Keys, Domain)
#   tags:
#     - profile
#     - moritz
# ---
{
  name = "moritz";
  domain = "nix.m7c5.de";
  description = "moritz";
  shell = "bash";
  extraGroups = [ "networkmanager" "wheel" ];
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvttE1EzwLJpzFc/LuuXZP485Ma0mEJQiu3iMXaO58W"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
  ];
}