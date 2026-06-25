# ---
# meta:
#   id: NIXH-05-LIB-001
#   layer: 5
#   role: lib
#   purpose: Zentrale Hostname-Tabelle für *.nix.m7c5.de — eine Wahrheit für Caddy vHosts
#   docs:
#     - docs/SPEC_REGISTRY.md
#   tags:
#     - dns
#     - caddy
#     - ssot
# ---
{ domain }:

let
  fqdn = sub: "${sub}.${domain}";

  # Schlüssel = Service-/Modul-Name; Wert = live FQDN (kann vom Schlüssel abweichen)
  mapping = {
    jellyfin = fqdn "jellyfin";
    seerr = fqdn "seerr";
    sonarr = fqdn "sonarr";
    radarr = fqdn "radarr";
    readarr = fqdn "readarr";
    prowlarr = fqdn "prowlarr";
    sabnzbd = fqdn "sabnzbd";
    audiobookshelf = fqdn "audiobookshelf";

    vaultwarden = fqdn "vault";
    homepage = fqdn "dashboard";
    filebrowser = fqdn "files";
    linkwarden = fqdn "links";
    "open-webui" = fqdn "ai";
    "home-assistant" = fqdn "home";
    "pocket-id" = fqdn "auth";
    blocky = fqdn "dns";
    paperless = fqdn "paperless";
    n8n = fqdn "n8n";
    gatus = fqdn "gatus";
    scrutiny = fqdn "scrutiny";
    grafana = fqdn "grafana";
    forgejo = fqdn "git";
    semaphore = fqdn "semaphore";
    cockpit = fqdn "admin";
    amp = fqdn "amp";
    "zigbee-stack" = fqdn "zigbee";
    ddns-updater = fqdn "ddns";
  };
in
{
  inherit domain mapping;

  host =
    key:
    if builtins.hasAttr key mapping then mapping.${key} else fqdn key;
}