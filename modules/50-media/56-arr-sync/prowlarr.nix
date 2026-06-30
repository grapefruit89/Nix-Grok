{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgProwlarr = config.my.services.prowlarr;
  cfgSync = config.my.media.sync.prowlarr;
  ports = config.my.ports;

  vpnConn = import ../../../lib/vpn-connection.nix { inherit lib; };
  vpnCfg = config.my.services.vpn-confinement;
  prowlarrHost = vpnConn.connectionAddress vpnCfg "prowlarr";
  hostBridgeAddr = vpnConn.hostBridgeAddress vpnCfg "prowlarr";
  prowlarrInVpn = vpnConn.isVpnConfined vpnCfg "prowlarr";

  # Arr-Applications die automatisch in Prowlarr registriert werden.
  # Alle aktivierten Arr-Services werden erfasst (kein manueller Eintrag nötig).
  autoApps = lib.filterAttrs (_: v: v.enabled) {
    sonarr = {
      enabled = config.my.services.sonarr.enable;
      port = ports.sonarr;
      host = hostBridgeAddr;
    };
    radarr = {
      enabled = config.my.services.radarr.enable;
      port = ports.radarr;
      host = hostBridgeAddr;
    };
    readarr = {
      enabled = config.my.services.readarr.enable;
      port = ports.readarr;
      host = hostBridgeAddr;
    };
    lidarr = {
      enabled = config.my.services.lidarr.enable;
      port = ports.lidarr;
      host = hostBridgeAddr;
    };
  };

  # Indexer-JSON für das Sync-Script generieren
  indexersJson = builtins.toJSON cfgSync.indexers;

  # Arr-Application-JSON für das Sync-Script generieren
  appsJson = builtins.toJSON (
    lib.mapAttrsToList (name: app: {
      inherit name;
      port = app.port;
      host = app.host;
      apiKeyFile = "/var/lib/secrets/${name}_api_key";
    }) autoApps
  );

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.media.sync.prowlarr = {
    enable = lib.mkEnableOption "Deklarativer Prowlarr-Sync (Indexer + Application-Registrierungen)";

    syncLevel = lib.mkOption {
      type = lib.types.enum [
        "AddOnly"
        "AddAndRemoveOnly"
        "FullSync"
      ];
      default = "AddAndRemoveOnly";
      description = "Prowlarr-Sync-Level für Arr-Application-Registrierungen.";
    };

    indexers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Indexer-Name in Prowlarr.";
            };
            protocol = lib.mkOption {
              type = lib.types.str;
              default = "usenet";
              description = "Protokoll: usenet oder torrent.";
            };
            implementation = lib.mkOption {
              type = lib.types.str;
              default = "Newznab";
              description = "Prowlarr-Indexer-Implementation (z.B. Newznab, Torznab).";
            };
            configContract = lib.mkOption {
              type = lib.types.str;
              default = "NewznabSettings";
              description = "Prowlarr configContract (muss zur Implementation passen).";
            };
            baseUrl = lib.mkOption {
              type = lib.types.str;
              description = "Basis-URL des Indexers.";
            };
            apiKeyFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Pfad zur Datei mit dem Indexer-API-Key (leer = kein Key nötig).";
            };
          };
        }
      );
      default = [ ];
      description = "Usenet/Torrent-Indexer, die deklarativ in Prowlarr registriert werden.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf (cfgProwlarr.enable && cfgSync.enable) {
    systemd.services.arr-sync-prowlarr = {
      description = "Declarative Prowlarr: Indexer + Application Registration";
      after = [
        "prowlarr.service"
      ]
      ++ lib.optional config.my.services.sonarr.enable "sonarr.service"
      ++ lib.optional config.my.services.radarr.enable "radarr.service"
      ++ lib.optional prowlarrInVpn "vpn-netns@prowlarr.service";
      wants = [ "prowlarr.service" ];
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
        # Retry: VPN braucht nach Boot manchmal einen Moment
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = "600s";
      };

      environment = {
        PROWLARR_HOST = prowlarrHost;
        PROWLARR_PORT = toString ports.prowlarr;
        PROWLARR_KEY_FILE = "/var/lib/secrets/prowlarr_api_key";
        HOST_BRIDGE = hostBridgeAddr;
        SYNC_LEVEL = cfgSync.syncLevel;
        INDEXERS_JSON = indexersJson;
        APPS_JSON = appsJson;
      };

      script = ''
        # Prowlarr-API-Key prüfen
        if [ ! -f "$PROWLARR_KEY_FILE" ]; then
          echo "Prowlarr API-Key-Datei fehlt: $PROWLARR_KEY_FILE — Sync übersprungen."
          exit 0
        fi
        PROWLARR_KEY=$(cat "$PROWLARR_KEY_FILE")

        # Prowlarr-Erreichbarkeit prüfen (max 60s warten)
        API="http://$PROWLARR_HOST:$PROWLARR_PORT"
        echo "Warte auf Prowlarr bei $API..."
        for i in $(seq 1 30); do
          if curl -sf --max-time 5 \
               -H "X-Api-Key: $PROWLARR_KEY" \
               "$API/api/v1/system/status" >/dev/null 2>&1; then
            echo "Prowlarr erreichbar (Versuch $i)."
            break
          fi
          [ "$i" -eq 30 ] && {
            echo "Prowlarr nicht erreichbar nach 60s — Sync übersprungen."
            echo "Tipp: VPN aktiv? Prowlarr läuft? (vpn-confinement: ${lib.boolToString prowlarrInVpn})"
            exit 0
          }
          sleep 2
        done

        # ── INDEXER REGISTRIEREN ──────────────────────────────────────────────
        echo "=== Prowlarr: Indexer-Registrierung ==="
        CURRENT_INDEXERS=$(curl -sf -H "X-Api-Key: $PROWLARR_KEY" "$API/api/v1/indexer")

        echo "$INDEXERS_JSON" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r indexer; do
          NAME=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.name')
          EXISTS=$(echo "$CURRENT_INDEXERS" | ${pkgs.jq}/bin/jq -r --arg n "$NAME" \
            '.[] | select(.name == $n) | .id // empty')

          if [ -z "$EXISTS" ]; then
            APIKEY_FILE=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.apiKeyFile')
            APIKEY=""
            [ -n "$APIKEY_FILE" ] && [ -f "$APIKEY_FILE" ] && APIKEY=$(cat "$APIKEY_FILE")

            PAYLOAD=$(echo "$indexer" | ${pkgs.jq}/bin/jq \
              --arg key "$APIKEY" \
              '{
                name: .name,
                enable: true,
                protocol: .protocol,
                implementation: .implementation,
                configContract: .configContract,
                fields: [
                  { name: "baseUrl", value: .baseUrl },
                  { name: "apiKey", value: $key }
                ]
              }')

            if curl -sf -X POST \
                 -H "X-Api-Key: $PROWLARR_KEY" \
                 -H "Content-Type: application/json" \
                 -d "$PAYLOAD" \
                 "$API/api/v1/indexer" >/dev/null; then
              echo "Indexer $NAME registriert."
            else
              echo "Fehler beim Registrieren von Indexer $NAME." >&2
            fi
          else
            echo "Indexer $NAME bereits vorhanden (ID: $EXISTS) — übersprungen."
          fi
        done

        # ── ARR-APPLICATIONS REGISTRIEREN ────────────────────────────────────
        echo "=== Prowlarr: Application-Registrierung ==="
        CURRENT_APPS=$(curl -sf -H "X-Api-Key: $PROWLARR_KEY" "$API/api/v1/applications")

        echo "$APPS_JSON" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r app; do
          NAME=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.name')
          # Ersten Buchstaben groß: sonarr → Sonarr
          IMPL=$(echo "$NAME" | ${pkgs.coreutils}/bin/cut -c1 | tr '[:lower:]' '[:upper:]')
          IMPL="$IMPL$(echo "$NAME" | ${pkgs.coreutils}/bin/cut -c2-)"

          EXISTS=$(echo "$CURRENT_APPS" | ${pkgs.jq}/bin/jq -r --arg n "$IMPL" \
            '.[] | select(.name == $n) | .id // empty')

          if [ -z "$EXISTS" ]; then
            APIKEY_FILE=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.apiKeyFile')
            if [ ! -f "$APIKEY_FILE" ]; then
              echo "API-Key-Datei fehlt: $APIKEY_FILE — $IMPL übersprungen."
              continue
            fi
            APIKEY=$(cat "$APIKEY_FILE")
            PORT=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.port')
            HOST=$(echo "$app" | ${pkgs.jq}/bin/jq -r '.host')

            echo "Registriere Application: $IMPL (http://$HOST:$PORT)"

            PAYLOAD=$(${pkgs.jq}/bin/jq -n \
              --arg name "$IMPL" \
              --arg impl "$IMPL" \
              --arg prowlarrUrl "$API" \
              --arg baseUrl "http://$HOST:$PORT" \
              --arg apikey "$APIKEY" \
              --arg syncLevel "$SYNC_LEVEL" \
              '{
                name: $name,
                enable: true,
                implementation: $impl,
                implementationName: $impl,
                configContract: "\($impl)Settings",
                syncLevel: $syncLevel,
                fields: [
                  { name: "prowlarrUrl", value: $prowlarrUrl },
                  { name: "baseUrl", value: $baseUrl },
                  { name: "apikey", value: $apikey }
                ]
              }')

            if curl -sf -X POST \
                 -H "X-Api-Key: $PROWLARR_KEY" \
                 -H "Content-Type: application/json" \
                 -d "$PAYLOAD" \
                 "$API/api/v1/applications" >/dev/null; then
              echo "Application $IMPL registriert."
            else
              echo "Fehler beim Registrieren von Application $IMPL." >&2
            fi
          else
            echo "Application $IMPL bereits vorhanden (ID: $EXISTS) — übersprungen."
          fi
        done

        # ── APPLICATION SYNC TRIGGERN ─────────────────────────────────────────
        echo "=== Prowlarr: Application-Sync triggern ==="
        curl -sf -X POST \
          -H "X-Api-Key: $PROWLARR_KEY" \
          -H "Content-Type: application/json" \
          -d '{"name":"ApplicationsSync"}' \
          "$API/api/v1/command" >/dev/null
        echo "Application-Sync-Command gesendet. Prowlarr-Sync abgeschlossen."
      '';
    };
  };
}
