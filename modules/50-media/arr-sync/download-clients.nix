{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgSync = config.my.media.sync.downloadClients;
  cfgSabnzbd = config.my.services.sabnzbd;
  ports = config.my.ports;

  vpnConn = import ../../../lib/vpn-connection.nix { inherit lib; };
  vpnCfg = config.my.services.vpn-confinement;
  sabHost = vpnConn.connectionAddress vpnCfg "sabnzbd";
  sabPort = ports.sabnzbd;
  hostBridgeAddr = vpnConn.hostBridgeAddress vpnCfg "sabnzbd";

  # Arr-Services die einen Download-Client brauchen.
  # Jeder Eintrag: Service-Name → { port, apiVersion, category }
  arrTargets = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = config.my.services.sonarr.enable;
      port = ports.sonarr;
      apiVersion = "v3";
      category = cfgSync.sonarr.category;
    };
    radarr = {
      enabled = config.my.services.radarr.enable;
      port = ports.radarr;
      apiVersion = "v3";
      category = cfgSync.radarr.category;
    };
    readarr = {
      enabled = config.my.services.readarr.enable;
      port = ports.readarr;
      apiVersion = "v1";
      category = cfgSync.readarr.category;
    };
    lidarr = {
      enabled = config.my.services.lidarr.enable;
      port = ports.lidarr;
      apiVersion = "v1";
      category = cfgSync.lidarr.category;
    };
  };

  targetsJson = builtins.toJSON (
    lib.mapAttrsToList (name: t: {
      inherit name;
      port = t.port;
      apiVersion = t.apiVersion;
      category = t.category;
      apiKeyFile = "/var/lib/secrets/${name}_api_key";
    }) arrTargets
  );

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.media.sync.downloadClients = {
    enable = lib.mkEnableOption "Deklarative SABnzbd-Download-Client-Registrierung in *Arr-Services";

    sonarr.category = lib.mkOption {
      type = lib.types.str;
      default = "tv";
      description = "SABnzbd-Kategorie für Sonarr-Downloads.";
    };
    radarr.category = lib.mkOption {
      type = lib.types.str;
      default = "movies";
      description = "SABnzbd-Kategorie für Radarr-Downloads.";
    };
    readarr.category = lib.mkOption {
      type = lib.types.str;
      default = "audiobooks";
      description = "SABnzbd-Kategorie für Readarr-Downloads.";
    };
    lidarr.category = lib.mkOption {
      type = lib.types.str;
      default = "music";
      description = "SABnzbd-Kategorie für Lidarr-Downloads.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf (cfgSabnzbd.enable && cfgSync.enable && arrTargets != { }) {
    systemd.services.arr-sync-download-clients = {
      description = "Declarative SABnzbd Download-Client Registration in *Arr";
      # Warten bis alle beteiligten Services laufen
      after = [ "sabnzbd.service" ] ++ lib.mapAttrsToList (name: _: "${name}.service") arrTargets;
      wants = [ "sabnzbd.service" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        curl
        jq
        coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 3;
        StartLimitIntervalSec = "300s";
      };

      environment = {
        SAB_HOST = sabHost;
        SAB_PORT = toString sabPort;
        SAB_KEY_FILE = "/var/lib/secrets/sabnzbd_api_key";
        HOST_BRIDGE = hostBridgeAddr;
        TARGETS_JSON = targetsJson;
      };

      script = ''
        # SABnzbd-API-Key prüfen
        if [ ! -f "$SAB_KEY_FILE" ]; then
          echo "SABnzbd API-Key-Datei fehlt: $SAB_KEY_FILE — Download-Client-Sync übersprungen."
          exit 0
        fi
        SAB_KEY=$(cat "$SAB_KEY_FILE")

        # SABnzbd-Erreichbarkeit prüfen (max 60s)
        echo "Warte auf SABnzbd bei http://$SAB_HOST:$SAB_PORT..."
        for i in $(seq 1 30); do
          if curl -sf --max-time 5 \
               "http://$SAB_HOST:$SAB_PORT/api?apikey=$SAB_KEY&mode=version" >/dev/null 2>&1; then
            echo "SABnzbd erreichbar (Versuch $i)."
            break
          fi
          [ "$i" -eq 30 ] && {
            echo "SABnzbd nicht erreichbar nach 60s — Sync übersprungen."
            exit 0
          }
          sleep 2
        done

        # ── DOWNLOAD-CLIENT IN JEDEM *ARR REGISTRIEREN ───────────────────────
        echo "$TARGETS_JSON" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r target; do
          NAME=$(echo "$target" | ${pkgs.jq}/bin/jq -r '.name')
          PORT=$(echo "$target" | ${pkgs.jq}/bin/jq -r '.port')
          API_VER=$(echo "$target" | ${pkgs.jq}/bin/jq -r '.apiVersion')
          CATEGORY=$(echo "$target" | ${pkgs.jq}/bin/jq -r '.category')
          APIKEY_FILE=$(echo "$target" | ${pkgs.jq}/bin/jq -r '.apiKeyFile')
          IMPL=$(echo "$NAME" | ${pkgs.coreutils}/bin/cut -c1 | tr '[:lower:]' '[:upper:]')
          IMPL="$IMPL$(echo "$NAME" | ${pkgs.coreutils}/bin/cut -c2-)"

          if [ ! -f "$APIKEY_FILE" ]; then
            echo "$IMPL: API-Key-Datei fehlt ($APIKEY_FILE) — übersprungen."
            continue
          fi
          APIKEY=$(cat "$APIKEY_FILE")
          ARR_API="http://$HOST_BRIDGE:$PORT/api/$API_VER"

          # Warten bis dieser Arr-Service erreichbar ist (max 30s)
          for j in $(seq 1 15); do
            if curl -sf --max-time 5 \
                 -H "X-Api-Key: $APIKEY" \
                 "$ARR_API/system/status" >/dev/null 2>&1; then
              break
            fi
            [ "$j" -eq 15 ] && {
              echo "$IMPL: nicht erreichbar — übersprungen."
              continue 2
            }
            sleep 2
          done

          # Prüfen ob SABnzbd schon registriert ist
          EXISTING=$(curl -sf -H "X-Api-Key: $APIKEY" "$ARR_API/downloadclient" | \
            ${pkgs.jq}/bin/jq -r '.[] | select(.implementation == "Sabnzbd") | .id // empty')

          if [ -z "$EXISTING" ]; then
            echo "$IMPL: SABnzbd als Download-Client registrieren (Kategorie: $CATEGORY)..."

            PAYLOAD=$(${pkgs.jq}/bin/jq -n \
              --arg sabHost "$SAB_HOST" \
              --argjson sabPort "$SAB_PORT" \
              --arg sabKey "$SAB_KEY" \
              --arg category "$CATEGORY" \
              '{
                enable: true,
                name: "SABnzbd",
                protocol: "usenet",
                priority: 1,
                implementationName: "SABnzbd",
                implementation: "Sabnzbd",
                configContract: "SabnzbdSettings",
                fields: [
                  { name: "host", value: $sabHost },
                  { name: "port", value: $sabPort },
                  { name: "useSsl", value: false },
                  { name: "apiKey", value: $sabKey },
                  { name: "category", value: $category }
                ]
              }')

            if curl -sf -X POST \
                 -H "X-Api-Key: $APIKEY" \
                 -H "Content-Type: application/json" \
                 -d "$PAYLOAD" \
                 "$ARR_API/downloadclient" >/dev/null; then
              echo "$IMPL: SABnzbd (Kategorie: $CATEGORY) registriert."
            else
              echo "$IMPL: Fehler beim Registrieren von SABnzbd." >&2
            fi
          else
            echo "$IMPL: SABnzbd bereits registriert (ID: $EXISTING) — übersprungen."
          fi
        done

        echo "Download-Client-Sync abgeschlossen."
      '';
    };
  };
}
