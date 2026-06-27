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
    # Schema: UID = Port = Ordner-Präfix (50xx = 50-media)
    sonarr   = 5003;  # war 989
    radarr   = 5004;  # war 978
    readarr  = 5005;  # war 987
    prowlarr = 5006;  # war 969
    sabnzbd  = 5007;  # war 984
  };

  defaultGroups = {
    media    = 169;   # BEHALTEN — Filesystem-Kompatibilität (chown -R root:media)
    sonarr   = 5003;
    radarr   = 5004;
    readarr  = 5005;
    prowlarr = 5006;
    sabnzbd  = 5007;
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
      assertion =
        (lib.length (lib.attrValues groups)) == (lib.length (lib.unique (lib.attrValues groups)));
      message = "[UID-REGISTRY] Doppelte GIDs in my.groups.registry";
    }
  ];
}
