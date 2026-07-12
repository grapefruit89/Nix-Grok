{ ... }:
{
  imports = [
    ./05-forbidden-tech.nix
    ./90-policy.nix
    ./91-security-assertions.nix
    ./92-on-demand.nix
    ./93-memory-pressure.nix
  ];
}
