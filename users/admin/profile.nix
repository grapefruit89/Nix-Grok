# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Einzige Datenquelle aller Admin-User-Werte (Name, Keys, Domain, Git)
#   tags:
#     - profile
#     - user
# ---
# Um den SSH-Benutzernamen zu ändern: nur `name` hier anpassen + nixos-rebuild switch
# + sudo usermod -l <neuer-name> -d /home/<neuer-name> -m admin (als root/TTY)
let
  baseDomain = "m7c5.de";
  # Nix-Subdomain-Präfix — leer lassen ("") um Services direkt unter m7c5.de zu schalten.
  # Solange Unraid nix.m7c5.de nicht belegt: "nix" → services unter service.nix.m7c5.de
  nixSubdomain = "nix";
in
{
  name = "admin";
  inherit baseDomain nixSubdomain;
  domain = if nixSubdomain != "" then "${nixSubdomain}.${baseDomain}" else baseDomain;
  description = "Admin";
  shell = "bash";
  extraGroups = [
    "networkmanager"
    "wheel"
  ];
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvttE1EzwLJpzFc/LuuXZP485Ma0mEJQiu3iMXaO58W"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRDbyFjT4SEL8yxNwZuEBPORD82qlJJhdr2r4qz1vCX"
  ];
  git = {
    name = "grapefruit89";
    email = "moritzbaumeister@gmail.com";
  };
}
