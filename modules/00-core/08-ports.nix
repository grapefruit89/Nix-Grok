# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Zentrale Port-Registry — alle my.ports.* Optionen als Single Source of Truth
#   docs:
#     - docs/adr/011-unified-port-uid-schema.md
#   tags:
#     - ports
#     - core
# ---
{ lib, ... }:
{
  options.my.ports = {
    technitium-dns = lib.mkOption {
      type = lib.types.port;
      default = 1002;
      description = "Technitium DNS Server web UI port (1002).";
    };
    valkey = lib.mkOption {
      type = lib.types.port;
      default = 6379;
      description = "Valkey cache port.";
    };
    ssh = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "SSH port (override via machines/<host>/profile.nix).";
    };
    jellyfin = lib.mkOption {
      type = lib.types.port;
      default = 5001;
      description = "Jellyfin port.";
    };
    jellyseerr = lib.mkOption {
      type = lib.types.port;
      default = 5002;
      description = "Jellyseerr port.";
    };
    sonarr = lib.mkOption {
      type = lib.types.port;
      default = 5003;
      description = "Sonarr port.";
    };
    radarr = lib.mkOption {
      type = lib.types.port;
      default = 5004;
      description = "Radarr port.";
    };
    readarr = lib.mkOption {
      type = lib.types.port;
      default = 5005;
      description = "Readarr port.";
    };
    prowlarr = lib.mkOption {
      type = lib.types.port;
      default = 5006;
      description = "Prowlarr port.";
    };
    sabnzbd = lib.mkOption {
      type = lib.types.port;
      default = 5007;
      description = "SABnzbd port.";
    };
    audiobookshelf = lib.mkOption {
      type = lib.types.port;
      default = 5008;
      description = "Audiobookshelf port.";
    };
    navidrome = lib.mkOption {
      type = lib.types.port;
      default = 5009;
      description = "Navidrome Music Server port.";
    };
    lidarr = lib.mkOption {
      type = lib.types.port;
      default = 5010;
      description = "Lidarr Music Downloader port.";
    };
    ddns-updater = lib.mkOption {
      type = lib.types.port;
      default = 1003;
      description = "DDNS-Updater WebUI/API port.";
    };
    vaultwarden = lib.mkOption {
      type = lib.types.port;
      default = 6001;
      description = "Vaultwarden port.";
    };
    homepage = lib.mkOption {
      type = lib.types.port;
      default = 6002;
      description = "Homepage port.";
    };
    mqtt = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT broker port.";
    };
    zigbee2mqtt = lib.mkOption {
      type = lib.types.port;
      default = 1004;
      description = "Zigbee2MQTT frontend port.";
    };
    pocket-id = lib.mkOption {
      type = lib.types.port;
      default = 1001;
      description = "PocketID port.";
    };
    paperless = lib.mkOption {
      type = lib.types.port;
      default = 6003;
      description = "Paperless-ngx port.";
    };
    filebrowser = lib.mkOption {
      type = lib.types.port;
      default = 6005;
      description = "Filebrowser port.";
    };
    linkwarden = lib.mkOption {
      type = lib.types.port;
      default = 6006;
      description = "Linkwarden port.";
    };
    open-webui = lib.mkOption {
      type = lib.types.port;
      default = 6007;
      description = "Open WebUI port.";
    };
    cockpit = lib.mkOption {
      type = lib.types.port;
      default = 7003;
      description = "Cockpit admin port.";
    };
    amp = lib.mkOption {
      type = lib.types.port;
      default = 7004;
      description = "AMP Web UI port.";
    };
    crowdsec = lib.mkOption {
      type = lib.types.port;
      default = 4004;
      description = "CrowdSec LAPI port.";
    };
    gatus = lib.mkOption {
      type = lib.types.port;
      default = 4003;
      description = "Gatus Web UI port.";
    };
    scrutiny = lib.mkOption {
      type = lib.types.port;
      default = 4005;
      description = "Scrutiny SMART dashboard port.";
    };
    victoriametrics = lib.mkOption {
      type = lib.types.port;
      default = 4006;
      description = "VictoriaMetrics TSDB port.";
    };
    loki = lib.mkOption {
      type = lib.types.port;
      default = 4002;
      description = "Loki API port.";
    };
    grafana = lib.mkOption {
      type = lib.types.port;
      default = 4001;
      description = "Grafana Web UI port.";
    };
  };
}
