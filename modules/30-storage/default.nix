{...}: {
  imports = [
    ./05-storage-policy.nix
    ./05-deferred-ops.nix
    ./30-storage.nix
    ./35-automount.nix
    ./36-disk-health.nix
  ];
}
