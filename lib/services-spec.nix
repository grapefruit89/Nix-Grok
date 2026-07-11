# ---
# meta:
#   id: NIXH-05-LIB-006
#   layer: 5
#   role: lib
#   purpose: Service-Spec-Matrix — Zonen, Ports/Sockets, Port-Konflikt-Assertions
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/ROADMAP.md
#   tags:
#     - services-spec
#     - ports
#     - zoning
# ---
{ lib }:
let
  zones = [
    "loopback"
    "internal"
    "external"
    "streaming"
  ];

  specEntryType = lib.types.submodule {
    options = {
      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
      };
      socket = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Unix socket path (preferred over TCP where supported).";
      };
      zone = lib.mkOption {
        type = lib.types.enum zones;
        description = "Trust zone for ingress and auth policy.";
      };
      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Ingress subdomain before identity.domain (SSoT with dns-map). null = no Caddy vHost.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
    };
  };

  # Ports die in der Spec-Matrix vorkommen — nur TCP, keine Sockets
  collectSpecPorts = spec: lib.filter (p: p != null) (map (s: s.port or null) (lib.attrValues spec));

  findDuplicatePorts =
    ports:
    let
      counted = lib.foldl' (
        acc: port:
        acc
        // {
          ${toString port} = (acc.${toString port} or 0) + 1;
        }
      ) { } ports;
      dups = lib.filter (p: counted.${toString p} > 1) (lib.unique ports);
    in
    dups;

  mkDefaultSpec = ports: sockets: {
    # --- loopback (kein Caddy-Ingress) ---
    postgresql = {
      socket = sockets.postgresql;
      zone = "loopback";
      description = "PostgreSQL";
    };
    valkey = {
      socket = sockets.valkey;
      zone = "loopback";
      description = "Valkey Cache";
    };
    crowdsec = {
      port = ports.crowdsec;
      zone = "loopback";
      description = "CrowdSec LAPI";
    };
    loki = {
      port = ports.loki;
      zone = "loopback";
      description = "Loki ingest";
    };

    # --- internal (LAN only, private_admin) ---
    gatus = {
      port = ports.gatus;
      zone = "internal";
      subdomain = "gatus";
      description = "Health Dashboard";
    };
    scrutiny = {
      port = ports.scrutiny;
      zone = "internal";
      subdomain = "scrutiny";
      description = "SMART Disk Health";
    };
    grafana = {
      socket = sockets.grafana;
      zone = "internal";
      subdomain = "grafana";
      description = "Metrics UI";
    };
    secrets-portal = {
      socket = sockets.secrets-portal;
      zone = "internal";
      subdomain = "secrets";
      description = "Credential Rotation Portal";
    };
    sabnzbd = {
      port = ports.sabnzbd;
      zone = "internal";
      subdomain = "sabnzbd";
      description = "Usenet (VPN-confined)";
    };
    blocky = {
      port = ports.blocky;
      zone = "internal";
      subdomain = "dns";
      description = "Blocky DNS (ad-blocking, split-horizon)";
    };
    ddns-updater = {
      port = ports.ddns-updater;
      zone = "internal";
      subdomain = "ddns";
      description = "Cloudflare DDNS";
    };
    sonarr = {
      port = ports.sonarr;
      zone = "internal";
      subdomain = "sonarr";
      description = "TV";
    };
    radarr = {
      port = ports.radarr;
      zone = "internal";
      subdomain = "radarr";
      description = "Movies";
    };
    readarr = {
      port = ports.readarr;
      zone = "internal";
      subdomain = "readarr";
      description = "Books";
    };
    prowlarr = {
      port = ports.prowlarr;
      zone = "internal";
      subdomain = "prowlarr";
      description = "Indexers";
    };
    lidarr = {
      port = ports.lidarr;
      zone = "internal";
      subdomain = "lidarr";
      description = "Music Downloader (Companion zu Navidrome)";
    };
    vaultwarden = {
      port = ports.vaultwarden;
      zone = "internal";
      subdomain = "vault";
      description = "Passwords";
    };
    homepage = {
      port = ports.homepage;
      zone = "internal";
      subdomain = "dashboard";
      description = "Dashboard";
    };

    # --- external (Internet + LAN, Pocket-ID SSO) ---
    pocket-id = {
      port = ports.pocket-id;
      zone = "external";
      subdomain = "auth";
      description = "Identity Provider";
    };
    seerr = {
      port = ports.jellyseerr;
      zone = "external";
      subdomain = "seerr";
      description = "Media Requests";
    };
    filebrowser = {
      port = ports.filebrowser;
      zone = "external";
      subdomain = "files";
      description = "Files";
    };
    shiori = {
      port = ports.shiori;
      zone = "external";
      subdomain = "links";
      description = "Bookmarks";
    };
    libreseerr = {
      port = ports.libreseerr;
      zone = "external";
      subdomain = "libreseerr";
      description = "Book Requests";
    };
    open-webui = {
      port = ports.open-webui;
      zone = "external";
      subdomain = "ai";
      description = "LLM UI";
    };
    paperless = {
      port = ports.paperless;
      zone = "external";
      subdomain = "paperless";
      description = "Documents";
    };
    home-assistant = {
      port = ports.home-assistant;
      zone = "external";
      subdomain = "home";
      description = "Home Assistant";
    };
    zigbee-stack = {
      port = ports.zigbee2mqtt;
      zone = "external";
      subdomain = "zigbee";
      description = "Zigbee UI";
    };
    amp = {
      port = ports.amp;
      zone = "external";
      subdomain = "amp";
      description = "Game Server Panel";
    };

    # --- streaming (Internet + LAN, SSO + flush_interval=-1) ---
    jellyfin = {
      port = ports.jellyfin;
      zone = "streaming";
      subdomain = "jellyfin";
      description = "Media";
    };
    navidrome = {
      port = ports.navidrome;
      zone = "streaming";
      subdomain = "music";
      description = "Music Server (API bypass für SubSonic-Clients)";
    };
    audiobookshelf = {
      port = ports.audiobookshelf;
      zone = "streaming";
      subdomain = "audiobookshelf";
      description = "Audiobooks";
    };
  };
in
{
  inherit
    zones
    specEntryType
    mkDefaultSpec
    collectSpecPorts
    findDuplicatePorts
    ;

  portRegistryAssertion =
    ports:
    let
      values = lib.attrValues ports;
      dups = findDuplicatePorts values;
    in
    {
      assertion = dups == [ ];
      message = "[PORT-REGISTRY] Doppelte Einträge in my.ports: ${lib.concatStringsSep ", " (map toString dups)}";
    };

  specPortAssertion =
    spec:
    let
      ports = collectSpecPorts spec;
      dups = findDuplicatePorts ports;
    in
    {
      assertion = dups == [ ];
      message = "[SERVICES-SPEC] Doppelte Ports in my.services.spec: ${lib.concatStringsSep ", " (map toString dups)}";
    };
}
