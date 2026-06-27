# ---
# meta:
#   id: NIXH-05-UID-001
#   layer: 3
#   role: module
#   purpose: UID/GID Single Source of Truth — keine Live-Migration, nur Registry + Assertions
#   lib:
#     - lib/uid-registry.nix
#   tags:
#     - uid
#     - registry
# ---
{
  config,
  lib,
  ...
}:
let
  reg = import ../../lib/uid-registry.nix { inherit lib; };
in
{
  options.my = {
    users.registry = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = reg.defaultUsers;
      description = "Statische Service-UIDs (nur explizit verwaltete Dienste).";
    };

    groups.registry = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = reg.defaultGroups;
      description = "Statische Gruppen-GIDs.";
    };
  };

  config.assertions =
    reg.userAssertions config.my.users.registry ++ reg.groupAssertions config.my.groups.registry;
}
