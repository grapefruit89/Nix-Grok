# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Server-Landkarte — einheitliche ID, Port/Socket, UID, Modul
#   tags:
#     - server-map
#     - ports
#     - uid
# ---
# Konvention: ID = Port = UID = Ordner-Präfix (4-stellig)
# transport-Typen:
#   uds:PATH  — Unix Domain Socket (kein TCP, nur lokale IPC)
#   tcp:PORT  — interner Localhost-Port (hinter Caddy)
#   ext:PORT  — externer Port (Firewall, IoT, Protokollstandard — NICHT ändern)
_: {
  services = {
    # ── 10-network ─────────────────────────────────────────────────────────────
    pocket-id = {
      id = 1001;
      transport = "uds:/run/pocket-id/pocket-id.sock";
      module = "10-network";
      sso = true;
    };
    technitium-dns = {
      id = 1002;
      transport = "tcp:1002";
      module = "10-network";
      sso = false;
    };
    ddns-updater = {
      id = 1003;
      transport = "tcp:1003";
      module = "10-network";
      sso = false;
    };
    zigbee2mqtt = {
      id = 1004;
      transport = "tcp:1004";
      module = "10-network";
      sso = true;
    };
    mqtt = {
      id = null;
      transport = "ext:1883";
      module = "10-network";
      sso = false;
      note = "IANA-Standard, IoT";
    };
    # ── 40-observability ───────────────────────────────────────────────────────
    grafana = {
      id = 4001;
      transport = "uds:/run/grafana/grafana.sock";
      module = "40-observability";
      sso = true;
    };
    loki = {
      id = 4002;
      transport = "tcp:4002";
      module = "40-observability";
      sso = false;
      note = "intern, kein Caddy";
    };
    gatus = {
      id = 4003;
      transport = "uds:/run/gatus/gatus.sock";
      module = "40-observability";
      sso = true;
    };
    crowdsec = {
      id = 4004;
      transport = "tcp:4004";
      module = "40-observability";
      sso = false;
      note = "LAPI intern";
    };
    scrutiny = {
      id = 4005;
      transport = "tcp:4005";
      module = "40-observability";
      sso = true;
    };

    # ── 50-media ───────────────────────────────────────────────────────────────
    jellyfin = {
      id = 5001;
      uid = 5001;
      transport = "tcp:5001";
      module = "50-media";
      sso = true;
    };
    jellyseerr = {
      id = 5002;
      transport = "tcp:5002";
      module = "50-media";
      sso = true;
    };
    sonarr = {
      id = 5003;
      uid = 5003;
      transport = "tcp:5003";
      module = "50-media";
      sso = true;
    };
    radarr = {
      id = 5004;
      uid = 5004;
      transport = "tcp:5004";
      module = "50-media";
      sso = true;
    };
    readarr = {
      id = 5005;
      uid = 5005;
      transport = "tcp:5005";
      module = "50-media";
      sso = true;
    };
    prowlarr = {
      id = 5006;
      uid = 5006;
      transport = "tcp:5006";
      module = "50-media";
      sso = true;
    };
    sabnzbd = {
      id = 5007;
      uid = 5007;
      transport = "tcp:5007";
      module = "50-media";
      sso = true;
    };
    audiobookshelf = {
      id = 5008;
      transport = "tcp:5008";
      module = "50-media";
      sso = true;
    };

    # ── 60-apps ────────────────────────────────────────────────────────────────
    vaultwarden = {
      id = 6001;
      transport = "uds:/run/vaultwarden/vaultwarden.sock";
      module = "60-apps";
      sso = true;
    };
    homepage = {
      id = 6002;
      transport = "uds:/run/homepage/homepage.sock";
      module = "60-apps";
      sso = true;
    };
    paperless = {
      id = 6003;
      transport = "uds:/run/paperless/paperless.sock";
      module = "60-apps";
      sso = true;
    };
    filebrowser = {
      id = 6005;
      transport = "tcp:6005";
      module = "60-apps";
      sso = true;
    };
    linkwarden = {
      id = 6006;
      transport = "uds:/run/linkwarden/linkwarden.sock";
      module = "60-apps";
      sso = true;
    };
    open-webui = {
      id = 6007;
      transport = "uds:/run/open-webui/open-webui.sock";
      module = "60-apps";
      sso = true;
    };

    # ── 70-forge ───────────────────────────────────────────────────────────────
    semaphore = {
      id = 7002;
      transport = "uds:/run/semaphore/semaphore.sock";
      module = "70-forge";
      sso = true;
    };
    cockpit = {
      id = 7003;
      transport = "tcp:7003";
      module = "70-forge";
      sso = false;
    };
    amp = {
      id = 7004;
      transport = "tcp:7004";
      module = "70-forge";
      sso = false;
    };

    # ── unveränderliche Standard-Ports ─────────────────────────────────────────
    ssh = {
      id = null;
      transport = "ext:22";
      module = "00-core";
      sso = false;
      note = "IANA-Standard";
    };
    valkey = {
      id = null;
      transport = "uds:/run/redis-valkey/valkey.sock";
      module = "00-core";
      sso = false;
      note = "RESP2, Cache";
    };
  };
}
