# Eigenstaendiger Flake fuer die Rettungs-ISO.
#
# Bewusst getrennt vom Haupt-Flake: der verlangt machines/q958/profile.local.nix
# (gitignored, enthaelt Secrets). Die ISO muss aber auf JEDEM Rechner baubar
# sein, auch ohne diese Datei -- sonst kann man sich das Rettungsmedium genau
# dann nicht bauen, wenn man es braucht.
#
# Bauen:
#   cd iso && nix build .#iso
#   ls -lh result/iso/*.iso
{
  description = "q958 Rettungs- und Installations-ISO";

  inputs = {
    # Stable-Kanal. NixOS hat kein LTS -- 26.05 ist die aktuelle stabile
    # Veroeffentlichung (30.05.2026), gepflegt bis Ende 2026. Fuer ein
    # Rettungsmedium zaehlt Verlaesslichkeit, nicht Aktualitaet.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./iso.nix ];
      };

      packages.${system} = {
        iso = self.nixosConfigurations.iso.config.system.build.isoImage;
        default = self.nixosConfigurations.iso.config.system.build.isoImage;
      };
    };
}
