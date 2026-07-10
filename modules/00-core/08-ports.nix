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
# Port-Bereiche (Strategie):
#   1xxx  — Infra-Dienste (DNS, OIDC, DDNS, Zigbee2MQTT, MQTT)
#   4xxx  — Observability (Grafana, Loki, Gatus, CrowdSec, Scrutiny, VictoriaMetrics)
#   5xxx  — Media / *arr-Stack (Jellyfin, Sonarr, Radarr, Readarr, Prowlarr, SABnzbd, ...)
#   6xxx  — Nutzer-Apps (Vaultwarden, Homepage, Paperless, Filebrowser, Linkwarden, ...)
#   7xxx  — Admin-Tools (Cockpit, AMP)
#   Standard-Ports (22, 1883, 6379, 8123) behalten ihre kanonischen Werte.
{ lib, ... }:
{
  options.my.ports = {
    blocky = lib.mkOption {
      type = lib.types.port;
      default = 1002;
      description = "Blocky DNS HTTP API + Prometheus metrics port (1002).";
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
    home-assistant = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant Web UI port (kanonisch).";
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
    oauth2-proxy = lib.mkOption {
      type = lib.types.port;
      default = 4180;
      description = "oauth2-proxy Forward-Auth port (kanonisch).";
    };
    dropbear = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Dropbear rescue SSH port (Stage-2 + initrd).";
    };
    netbird-wg = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "Netbird WireGuard listen port.";
    };
    netbird-metrics = lib.mkOption {
      type = lib.types.port;
      default = 6061;
      description = "Netbird management metrics port (6062 = signal, 6060 = pprof builtin).";
    };
    node-exporter = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Prometheus node-exporter port (44-metrics).";
    };
    hermes = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Hermes Agent Gateway port (60-apps).";
    };
    wyoming-stt = lib.mkOption {
      type = lib.types.port;
      default = 10300;
      description = "Wyoming STT bridge port (Groq Whisper).";
    };
    wyoming-tts = lib.mkOption {
      type = lib.types.port;
      default = 10200;
      description = "Wyoming TTS bridge port (Google Cloud TTS).";
    };
    wyoming-edge-tts = lib.mkOption {
      type = lib.types.port;
      default = 10201;
      description = "Wyoming Edge TTS bridge port (Microsoft Edge TTS).";
    };
  };
}
