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
    "admin-hangar"
    "family-pocketid"
    "public"
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

  mkDefaultSpec = ports: {
    # --- loopback (kein Caddy-Ingress) ---
    postgresql = {
      socket = "/run/postgresql/.s.PGSQL.5432";
      zone = "loopback";
      description = "PostgreSQL";
    };
    valkey = {
      socket = "/run/redis-valkey/redis.sock";
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

    # --- admin-hangar (tailscale_admin / LAN) ---
    gatus = {
      port = ports.gatus;
      zone = "admin-hangar";
      subdomain = "gatus";
      description = "Health Dashboard";
    };
    scrutiny = {
      port = ports.scrutiny;
      zone = "admin-hangar";
      subdomain = "scrutiny";
      description = "SMART Disk Health";
    };
    grafana = {
      socket = "/run/grafana/grafana.sock";
      zone = "admin-hangar";
      subdomain = "grafana";
      description = "Metrics UI";
    };
    sabnzbd = {
      port = ports.sabnzbd;
      zone = "admin-hangar";
      subdomain = "sabnzbd";
      description = "Usenet (VPN-confined)";
    };
    cockpit = {
      port = ports.cockpit;
      zone = "admin-hangar";
      subdomain = "admin";
      description = "Host Admin";
    };
    blocky = {
      port = 53;
      zone = "admin-hangar";
      subdomain = "dns";
      description = "DNS Resolver UI";
    };
    ddns-updater = {
      port = ports.ddns-updater;
      zone = "admin-hangar";
      subdomain = "ddns";
      description = "Cloudflare DDNS";
    };

    # --- family-pocketid (Pocket-ID forward_auth) ---
    pocket-id = {
      port = ports.pocket-id;
      zone = "family-pocketid";
      subdomain = "auth";
      description = "Identity Provider";
    };
    jellyfin = {
      port = ports.jellyfin;
      zone = "family-pocketid";
      subdomain = "jellyfin";
      description = "Media (Client-Split SSO)";
    };
    seerr = {
      port = ports.jellyseerr;
      zone = "family-pocketid";
      subdomain = "seerr";
      description = "Media Requests";
    };
    sonarr = {
      port = ports.sonarr;
      zone = "family-pocketid";
      subdomain = "sonarr";
      description = "TV";
    };
    radarr = {
      port = ports.radarr;
      zone = "family-pocketid";
      subdomain = "radarr";
      description = "Movies";
    };
    readarr = {
      port = ports.readarr;
      zone = "family-pocketid";
      subdomain = "readarr";
      description = "Books";
    };
    prowlarr = {
      port = ports.prowlarr;
      zone = "family-pocketid";
      subdomain = "prowlarr";
      description = "Indexers";
    };
    audiobookshelf = {
      port = ports.audiobookshelf;
      zone = "family-pocketid";
      subdomain = "audiobookshelf";
      description = "Audiobooks";
    };
    vaultwarden = {
      port = ports.vaultwarden;
      zone = "family-pocketid";
      subdomain = "vault";
      description = "Passwords";
    };
    homepage = {
      port = ports.homepage;
      zone = "family-pocketid";
      subdomain = "dashboard";
      description = "Dashboard";
    };
    filebrowser = {
      port = ports.filebrowser;
      zone = "family-pocketid";
      subdomain = "files";
      description = "Files";
    };
    linkwarden = {
      port = ports.linkwarden;
      zone = "family-pocketid";
      subdomain = "links";
      description = "Bookmarks";
    };
    open-webui = {
      port = ports.open-webui;
      zone = "family-pocketid";
      subdomain = "ai";
      description = "LLM UI";
    };
    paperless = {
      port = ports.paperless;
      zone = "family-pocketid";
      subdomain = "paperless";
      description = "Documents";
    };
    n8n = {
      port = ports.n8n;
      zone = "family-pocketid";
      subdomain = "n8n";
      description = "Automation";
    };
    home-assistant = {
      port = 8123;
      zone = "family-pocketid";
      subdomain = "home";
      description = "Home Assistant";
    };
    zigbee-stack = {
      port = ports.zigbee2mqtt;
      zone = "family-pocketid";
      subdomain = "zigbee";
      description = "Zigbee UI";
    };
    forgejo = {
      socket = "/run/forgejo/forgejo.sock";
      zone = "family-pocketid";
      subdomain = "git";
      description = "Git Forge";
    };
    semaphore = {
      port = ports.semaphore;
      zone = "family-pocketid";
      subdomain = "semaphore";
      description = "Ansible UI";
    };
    amp = {
      port = ports.amp;
      zone = "family-pocketid";
      subdomain = "amp";
      description = "Game Server Panel";
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
