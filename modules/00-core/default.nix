# ---
# id: "core"
# domain: "00"
# status: "active"
# layer: 4
# purpose: "Domäne 00-core — aggregiert Bootstrap, UID-Registry, Services-Spec, Creds, Boot-Watchdog"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["core", "imports"]
# ---
{ ... }:
{
  imports = [
    ./01-core.nix
    ./02-nixmeta-ban.nix
    ./03-uid-registry.nix
    ./04-services-spec.nix
    ./05-creds.nix
    ./06-boot-watchdog.nix
    ./10-rebuild-watchdog.nix
    ./07-structure-validation.nix
    ./08-ports.nix
    ./09-network-routing.nix
    ./09-nix-tools.nix
  ];
}
