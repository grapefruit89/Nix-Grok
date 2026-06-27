{ ... }: {
  imports = [
    ./15-firewall.nix
    ./20-security.nix
    ./25-kernel-policy.nix
    ./26-kernel-hardening.nix
    ./27-hardened-core.nix
  ];
}
