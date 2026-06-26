# ---
# id: "core"
# domain: "00"
# status: "active"
# layer: 4
# purpose: "Domäne 00-core — aggregiert Bootstrap, UID-Registry, Services-Spec, SOPS, Boot-Watchdog"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["core", "imports"]
# ---
{ ... }:

{
  imports = [
    ./0010-core.nix
    ./0020-nixmeta-ban.nix
    ./0030-uid-registry.nix
    ./0040-services-spec.nix
    ./0050-sops.nix
    ./0060-boot-watchdog.nix
  ];
}
