# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Einzige Personen-SSoT — Name, Keys, Domain, Git, Locale-Quelle
#   tags:
#     - profile
#     - user
#     - jarvis
# ---
let
  baseDomain = "m7c5.de";
  nixSubdomain = "nix";
in
{
  name = "jarvis";
  description = "jarvis";
  inherit baseDomain nixSubdomain;
  domain = if nixSubdomain != "" then "${nixSubdomain}.${baseDomain}" else baseDomain;
  shell = "bash";
  extraGroups = [
    "networkmanager"
    "wheel"
  ];
  # Beide Login-Keys von q958 (/etc/ssh/authorized_keys.d/moritz) — SSoT für SSH + Recovery + LUKS-Unlock.
  # Key 1: persönlicher Login (privat, nie in GitHub-Account-Settings)
  # Key 2: zweiter Login (kann später als GitHub-Account-Public-Key hinterlegt werden)
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvttE1EzwLJpzFc/LuuXZP485Ma0mEJQiu3iMXaO58W"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
  ];
  git = {
    name = "grapefruit89";
    email = "moritzbaumeister@gmail.com";
  };
}
