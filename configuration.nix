# Kanonisch: nixos-rebuild switch --flake /etc/nixos#q958
{ ... }: {
  imports = [ ./machines/q958/default.nix ];
}