# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Gatus-Endpoint-Generator aus Service-Spec
#   tags:
#     - gatus
#     - observability
# ---
{
  lib,
  config,
}:
let
  ports = config.my.ports;
  sshPort = ports.ssh or 22;
  svc = config.my.services;
  vpnConn = import ./vpn-connection.nix { inherit lib; };
  vpnCfg = config.my.services.vpn-confinement;
  gatusPort = config.my.services.gatus.port or ports.gatus;

  local = "127.0.0.1";

  mediaHost =
    name: if vpnConn.isVpnConfined vpnCfg name then vpnConn.connectionAddress vpnCfg name else local;

  mkHttp =
    {
      name,
      group,
      host,
      port,
      path ? "/",
      interval ? "1m",
      status ? 200,
    }:
    {
      inherit name group interval;
      url = "http://${host}:${toString port}${path}";
      conditions = [ "[STATUS] == ${toString status}" ];
    };

  mkTcp =
    {
      name,
      group,
      host ? local,
      port,
      interval ? "1m",
    }:
    {
      inherit name group interval;
      url = "tcp://${host}:${toString port}";
      conditions = [ "[CONNECTED] == true" ];
    };

  mkDns =
    {
      name,
      group,
      queryName,
      interval ? "1m",
    }:
    {
      inherit name group interval;
      url = "dns://cloudflare.com";
      dns = {
        resolver = "${local}:53";
        query-name = queryName;
        query-type = "A";
      };
      conditions = [ "[DNS_RC] == NOERROR" ];
    };

  mkSsh =
    {
      name,
      group,
      command,
      interval ? "1m",
      timeout ? null,
    }:
    lib.recursiveUpdate {
      inherit name group interval;
      url = "ssh://${local}:${toString sshPort}";
      conditions = [
        "[CONNECTED] == true"
        "[STATUS] == 0"
        "[BODY] == OK*"
      ];
      ssh = {
        username = "monitoring";
        private-key = "/var/lib/gatus/ssh_key";
        body.command = command;
      };
    } (lib.optionalAttrs (timeout != null) { client.timeout = timeout; });

  core = [
    {
      name = "internet-ping";
      group = "network";
      url = "icmp://1.1.1.1";
      interval = "30s";
      conditions = [ "[CONNECTED] == true" ];
    }
    (mkTcp {
      name = "caddy-ingress";
      group = "critical";
      port = 443;
    })
    (mkDns {
      name = "blocky-dns";
      group = "critical";
      queryName = "cloudflare.com";
    })
  ];

  storage =
    lib.optionals (svc.storage.enable or false) [
      (mkSsh {
        name = "mergerfs-fast-pool";
        group = "storage";
        command = "/run/current-system/sw/bin/check-fast-pool";
        interval = "2m";
        timeout = "25s";
      })
      (mkSsh {
        name = "mergerfs-media-pool";
        group = "storage";
        command = "/run/current-system/sw/bin/check-media-pool";
        interval = "2m";
        timeout = "25s";
      })
      (mkSsh {
        name = "storage-permissions-drift";
        group = "storage";
        command = "/run/current-system/sw/bin/check-permissions-drift";
        interval = "1h";
      })
    ]
    ++ lib.optionals (svc.restic-backup.enable or false) [
      (mkSsh {
        name = "restic-backup-tier-a";
        group = "storage";
        command = "/run/current-system/sw/bin/check-restic-backup";
        interval = "1h";
      })
    ]
    ++ lib.optionals (config.my.disk-health.enable or false) [
      (mkSsh {
        name = "smartd-active";
        group = "storage";
        command = "/run/current-system/sw/bin/check-smartd-active";
      })
      (mkHttp {
        name = "scrutiny-health";
        group = "storage";
        host = local;
        port = ports.scrutiny;
        path = "/health";
      })
      (mkSsh {
        name = "hdd-smart";
        group = "storage";
        command = "/run/current-system/sw/bin/check-hdd-smart";
        interval = "6h";
        timeout = "30s";
      })
    ];

  dataServices =
    lib.optionals (svc.postgresql.enable or false) [
      (mkSsh {
        name = "postgresql";
        group = "critical";
        command = "/run/current-system/sw/bin/check-postgres-uds";
      })
    ]
    ++ lib.optionals (svc.valkey.enable or false) [
      (mkSsh {
        name = "valkey";
        group = "core";
        command = "/run/current-system/sw/bin/check-valkey-uds";
      })
    ];

  observability =
    lib.optionals (config.my.observability.enable or false) [
      (mkHttp {
        name = "loki";
        group = "observability";
        host = local;
        port = ports.loki;
        path = "/ready";
      })
      (mkSsh {
        name = "grafana";
        group = "observability";
        command = "/run/current-system/sw/bin/check-grafana-uds";
      })
    ]
    ++ [
      (mkHttp {
        name = "gatus-self";
        group = "observability";
        host = local;
        port = gatusPort;
        path = "/health";
      })
    ];

  media =
    lib.optionals svc.jellyfin.enable [
      (mkHttp {
        name = "jellyfin";
        group = "media";
        host = local;
        port = ports.jellyfin;
      })
    ]
    ++ lib.optionals svc.sonarr.enable [
      (mkHttp {
        name = "sonarr";
        group = "media";
        host = local;
        port = ports.sonarr;
      })
    ]
    ++ lib.optionals svc.radarr.enable [
      (mkHttp {
        name = "radarr";
        group = "media";
        host = local;
        port = ports.radarr;
      })
    ]
    ++ lib.optionals svc.readarr.enable [
      (mkHttp {
        name = "readarr";
        group = "media";
        host = local;
        port = ports.readarr;
      })
    ]
    ++ lib.optionals svc.prowlarr.enable [
      (mkHttp {
        name = "prowlarr";
        group = "media";
        host = mediaHost "prowlarr";
        port = ports.prowlarr;
      })
    ]
    ++ lib.optionals svc.sabnzbd.enable [
      (mkHttp {
        name = "sabnzbd";
        group = "media";
        host = mediaHost "sabnzbd";
        port = ports.sabnzbd;
      })
    ]
    ++ lib.optionals svc.jellyseerr.enable [
      (mkHttp {
        name = "jellyseerr";
        group = "media";
        host = local;
        port = ports.jellyseerr;
      })
    ]
    ++ lib.optionals svc.audiobookshelf.enable [
      (mkHttp {
        name = "audiobookshelf";
        group = "media";
        host = local;
        port = ports.audiobookshelf;
      })
    ];

  apps =
    lib.optionals svc.pocket-id.enable [
      (mkHttp {
        name = "pocket-id";
        group = "apps";
        host = local;
        port = ports.pocket-id;
      })
    ]
    ++ lib.optionals svc.vaultwarden.enable [
      (mkHttp {
        name = "vaultwarden";
        group = "apps";
        host = local;
        port = ports.vaultwarden;
        path = "/alive";
      })
    ]
    ++ lib.optionals svc.paperless.enable [
      (mkHttp {
        name = "paperless-ngx";
        group = "apps";
        host = local;
        port = ports.paperless;
        path = "/api/";
      })
    ]
    ++ lib.optionals svc.n8n.enable [
      (mkHttp {
        name = "n8n";
        group = "apps";
        host = local;
        port = ports.n8n;
        path = "/healthz";
      })
    ]
    ++ lib.optionals svc.open-webui.enable [
      (mkHttp {
        name = "open-webui";
        group = "apps";
        host = local;
        port = ports.open-webui;
        path = "/health";
      })
    ]
    ++ lib.optionals svc.linkwarden.enable [
      (mkHttp {
        name = "linkwarden";
        group = "apps";
        host = local;
        port = ports.linkwarden;
        path = "/api/health";
      })
    ]
    ++ lib.optionals svc.filebrowser.enable [
      (mkHttp {
        name = "filebrowser";
        group = "apps";
        host = local;
        port = ports.filebrowser;
        path = "/health";
      })
    ]
    ++ lib.optionals svc.homepage.enable [
      (mkHttp {
        name = "homepage";
        group = "apps";
        host = local;
        port = ports.homepage;
      })
    ];

  forge =
    lib.optionals (config.my.services.cockpit.enable or false) [
      (mkTcp {
        name = "cockpit";
        group = "forge";
        port = ports.cockpit;
      })
    ]
    ++ lib.optionals (config.my.services.amp.enable or false) [
      (mkHttp {
        name = "amp";
        group = "forge";
        host = local;
        port = ports.amp;
      })
    ];

  endpoints = core ++ storage ++ dataServices ++ observability ++ media ++ apps ++ forge;
in
{
  web = {
    address = local;
    port = gatusPort;
  };
  storage = {
    type = "sqlite";
    path = "/var/lib/gatus/data.db";
  };
  inherit endpoints;
}
