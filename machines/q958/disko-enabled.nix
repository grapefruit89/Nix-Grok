# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: disko-Runtime — fileSystems aus disko.nix wenn tierA.diskoManaged
#   docs:
#     - docs/adr/3024-disko-tier-a-provisioning.md
#     - machines/q958/disko-deprecations.json
#   tags:
#     - disko
# ---
# Aktiv wenn profile.nix → storage.tierA.diskoManaged = true (nach disko-q958.sh install + nixos-install)
# Liefert fileSystems aus disko.nix — ersetzt hardware.nix-Mounts (Phase 3 prune)
{
  lib,
  disko,
  self,
  ...
}:
let
  p = import ./profile.nix;
  diskoManaged = p.storage.tierA.diskoManaged or false;
in
{
  imports = lib.optionals diskoManaged [
    disko.nixosModules.disko
    self.diskoConfigurations.q958
  ];
}
