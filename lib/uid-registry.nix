# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Statische UID/GID-Registry für skuid und Reproduzierbarkeit
#   tags:
#     - uid
#     - security
# ---
{ lib }:

let
  defaultUsers = {
    # *arr + Usenet — explizit statisch (Split-Tunnel + nftables skuid)
    prowlarr = 969;
    sabnzbd = 984;
    sonarr = 989;
    radarr = 978;
    readarr = 987;
  };

  defaultGroups = {
    media = 169;
    sabnzbd = 194;
    prowlarr = 969;
    sonarr = 989;
    radarr = 978;
    readarr = 987;
  };

in
{
  inherit defaultUsers defaultGroups;

  getUser = registry: name: registry.${name} or (throw "uid-registry: unbekannter User '${name}'");

  getGroup = registry: name: registry.${name} or (throw "uid-registry: unbekannte Gruppe '${name}'");

  userAssertions = users: [
    {
      assertion = (lib.length (lib.attrValues users)) == (lib.length (lib.unique (lib.attrValues users)));
      message = "[UID-REGISTRY] Doppelte UIDs in my.users.registry";
    }
  ];

  groupAssertions = groups: [
    {
      assertion = (lib.length (lib.attrValues groups)) == (lib.length (lib.unique (lib.attrValues groups)));
      message = "[UID-REGISTRY] Doppelte GIDs in my.groups.registry";
    }
  ];
}