# ---
# meta:
#   id: NIXH-05-LIB-009
#   layer: 5
#   role: lib
#   purpose: Spec-Schlüssel → Service-enable für Ingress-Generator
#   tags:
#     - services-spec
#     - ingress
# ---
{ ... }:

let
  enabled =
    config: name:
    let
      mySvc = config.my.services or { };
      sec = config.my.security or { };
      checks = {
        postgresql = config.services.postgresql.enable or false;
        valkey = config.services.redis.servers.valkey.enable or false;
        crowdsec = sec.crowdsec.enable or false;
        loki = config.services.loki.enable or false;
        gatus = mySvc.gatus.enable or false;
        scrutiny = config.my.disk-health.enable or false;
        grafana = config.services.grafana.enable or false;
        sabnzbd = mySvc.sabnzbd.enable or false;
        cockpit = mySvc.cockpit.enable or false;
        blocky = mySvc.blocky.enable or false;
        ddns-updater = mySvc.ddns-updater.enable or false;
        pocket-id = mySvc.pocket-id.enable or false;
        jellyfin = mySvc.jellyfin.enable or false;
        seerr = mySvc.jellyseerr.enable or false;
        sonarr = mySvc.sonarr.enable or false;
        radarr = mySvc.radarr.enable or false;
        readarr = mySvc.readarr.enable or false;
        prowlarr = mySvc.prowlarr.enable or false;
        audiobookshelf = mySvc.audiobookshelf.enable or false;
        vaultwarden = mySvc.vaultwarden.enable or false;
        homepage = mySvc.homepage.enable or false;
        filebrowser = mySvc.filebrowser.enable or false;
        linkwarden = mySvc.linkwarden.enable or false;
        open-webui = mySvc.open-webui.enable or false;
        paperless = mySvc.paperless.enable or false;
        n8n = mySvc.n8n.enable or false;
        home-assistant = mySvc.home-assistant.enable or false;
        zigbee-stack = mySvc.zigbee-stack.enable or false;
        amp = mySvc.amp.enable or false;
      };
    in
    if builtins.hasAttr name checks then checks.${name} else false;
in
{
  inherit enabled;
}
