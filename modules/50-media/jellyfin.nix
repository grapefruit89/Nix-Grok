# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Jellyfin QuickSync + Jellyseerr hinter Caddy + Pocket-ID SSO-Plugin
#   docs:
#     - docs/memory_oom.md
#     - docs/adr/001-dns-dot-fail-closed.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - jellyfin
#     - seerr
#   tags:
#     - media
#     - jellyfin
#     - oidc
# ---
#
# Jellyfin SSO (jellyfin-plugin-sso v4.0.0.3):
#   1. Pocket-ID → Applications → New → Name: "Jellyfin"
#      Callback URL: https://jellyfin.DOMAIN/sso/OID/redirect/PocketID
#   2. client_id + client_secret in profile.local.nix:
#        secrets.oidc.jellyfin = { clientId = "…"; clientSecret = "…"; };
#   3. nixos-rebuild switch → /var/lib/secrets/jellyfin-oidc.env + SSO-Auth.xml erscheinen
#   4. In Jellyfin → Dashboard → Plugins → SSO-Auth: Provider "PocketID" sollte aktiv sein
#
# Jellyseerr nutzt Jellyfin-Auth → benötigt kein eigenes OIDC.
#
# Transcode-Strategie (ADR-001 Anhang):
#   - /run/jellyfin-transcode ist ein dediziertes tmpfs (8 GB Limit, RAM-backed)
#   - Segmente leben nie auf Disk → kein I/O-Wear, kein voll laufender ZFS-Pool
#   - Cleanup-Timer löscht Segmente älter als 60 min (verhindert stale session accumulation)
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  cfgJellyfin = config.my.services.jellyfin;
  cfgJellyseerr = config.my.services.jellyseerr;
  domain = config.my.configs.identity.domain;
  dnsMap = import ../../lib/dns-map.nix { inherit domain; };
  portJellyfin = config.my.ports.jellyfin;
  portJellyseerr = config.my.ports.jellyseerr;
  locale = config.my.configs.locale;
  localeLang = locale.language or "de";
  localeUi = lib.replaceStrings [ "_" ] [ "-" ] (locale.default or "de_DE.UTF-8");
  localeCc = lib.toUpper (lib.substring 3 2 localeUi);
  jellyfinUrl = "https://${dnsMap.host "jellyfin"}";

  # SSO-Plugin v4.0.0.3 — als Nix-Derivation aus GitHub-Release
  jellyfinSsoPlugin =
    pkgs.runCommand "jellyfin-plugin-sso"
      {
        src = pkgs.fetchurl {
          url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v4.0.0.3/sso-authentication_4.0.0.3.zip";
          hash = "sha256-3glRJVvsTtZGA3ZB5+CqEhCzoAoUFAZUgIe+2ZTLm90=";
        };
        nativeBuildInputs = [ pkgs.unzip ];
      }
      ''
        mkdir -p "$out"
        unzip "$src" -d "$out"
      '';

  jellyfinSsoXml = pkgs.writeText "jellyfin-sso-config.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <SSOConfigs>
        <OIDProviderConfig>
          <OIDEndpoint>https://auth.${domain}</OIDEndpoint>
          <OIDClientID>@CLIENT_ID@</OIDClientID>
          <OIDSecret>@CLIENT_SECRET@</OIDSecret>
          <Enabled>true</Enabled>
          <EnableAllFolders>true</EnableAllFolders>
          <EnableAuthorization>false</EnableAuthorization>
          <EnableAllUsers>true</EnableAllUsers>
          <SetDefaultProvider>true</SetDefaultProvider>
          <EnableFolderRoles>false</EnableFolderRoles>
        </OIDProviderConfig>
      </SSOConfigs>
      <BrandingOptions>
        <Options>
          <Provider>oidc</Provider>
          <DefaultProvider>PocketID</DefaultProvider>
        </Options>
      </BrandingOptions>
    </PluginConfiguration>
  '';

  jellyfinConfigSeeds = pkgs.runCommand "jellyfin-config-seeds" { } ''
    mkdir -p $out
    ${pkgs.gnused}/bin/sed \
      -e 's|@LOCALE_LANG@|${localeLang}|g' \
      -e 's|@LOCALE_CC@|${localeCc}|g' \
      -e 's|@LOCALE_UI@|${localeUi}|g' \
      ${./data/jellyfin-system.xml} > $out/system.xml
    ${pkgs.gnused}/bin/sed \
      -e 's|@JELLYFIN_URL@|${jellyfinUrl}|g' \
      ${./data/jellyfin-network.xml} > $out/network.xml
    # encoding.xml: VAAPI-Konfiguration für Intel iHD (i3-9100, Gen 9)
    cp ${./data/jellyfin-encoding.xml} $out/encoding.xml
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf cfgJellyfin.enable (
      lib.mkMerge [
        {
          services.jellyfin = {
            enable = true;
            openFirewall = false;
          };

          # Dediziertes tmpfs für Transcode-Segmente (8 GB, RAM-backed, kein Disk-I/O)
          fileSystems."/run/jellyfin-transcode" = {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "size=8g"
              "mode=0750"
              "nosuid"
              "nodev"
            ];
          };

          systemd.services.jellyfin.preStart = lib.mkBefore (
            ''
              install -d -m 0750 -o jellyfin -g jellyfin /var/lib/jellyfin/config
              for seed in system.xml network.xml encoding.xml; do
                if [ ! -f "/var/lib/jellyfin/config/$seed" ]; then
                  install -m 0640 -o jellyfin -g jellyfin \
                    ${jellyfinConfigSeeds}/$seed /var/lib/jellyfin/config/$seed
                fi
              done
              # Transcode-Dir Eigentümer setzen (tmpfs wird als root gemountet)
              chown jellyfin:jellyfin /run/jellyfin-transcode
            ''
            +
              # SSO-Plugin installieren (idempotent via Versionspfad)
              ''
                PLUGIN_DIR="/var/lib/jellyfin/plugins/sso-authentication_4.0.0.3"
                if [ ! -d "$PLUGIN_DIR" ]; then
                  install -d -m 0755 -o jellyfin -g jellyfin "$PLUGIN_DIR"
                  find ${jellyfinSsoPlugin} -maxdepth 3 \( -name "*.dll" -o -name "meta.json" \) | \
                    while read -r f; do
                      install -m 0644 -o jellyfin -g jellyfin "$f" "$PLUGIN_DIR/"
                    done
                fi

                # SSO-Konfiguration aus Secrets (nur wenn /var/lib/secrets/jellyfin-oidc.env existiert)
                if [ -f /var/lib/secrets/jellyfin-oidc.env ]; then
                  _JF_ID=$(grep -m1 '^ND_OIDCCLIENTID=' /var/lib/secrets/jellyfin-oidc.env | cut -d= -f2-)
                  _JF_SECRET=$(grep -m1 '^ND_OIDCCLIENTSECRET=' /var/lib/secrets/jellyfin-oidc.env | cut -d= -f2-)
                  install -d -m 0750 -o jellyfin -g jellyfin \
                    /var/lib/jellyfin/config/PluginConfiguration
                  ${pkgs.gnused}/bin/sed \
                    -e "s|@CLIENT_ID@|$_JF_ID|g" \
                    -e "s|@CLIENT_SECRET@|$_JF_SECRET|g" \
                    ${jellyfinSsoXml} | \
                    ${pkgs.coreutils}/bin/tee \
                      /var/lib/jellyfin/config/PluginConfiguration/SSO-Auth.xml > /dev/null
                  chown jellyfin:jellyfin /var/lib/jellyfin/config/PluginConfiguration/SSO-Auth.xml
                  chmod 0640 /var/lib/jellyfin/config/PluginConfiguration/SSO-Auth.xml
                  unset _JF_ID _JF_SECRET
                fi
              ''
          );

          # Cleanup-Timer: Segmente älter als 60 min löschen (verhindert volle tmpfs)
          systemd.timers.jellyfin-transcode-cleanup = {
            description = "Jellyfin: Stale Transcode-Segmente bereinigen";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "30min";
              Unit = "jellyfin-transcode-cleanup.service";
            };
          };

          systemd.services.jellyfin-transcode-cleanup = {
            description = "Jellyfin: Stale Transcode-Segmente löschen (>60min)";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript "jellyfin-transcode-cleanup" ''
                set -euo pipefail
                DIR="/run/jellyfin-transcode"
                [ -d "$DIR" ] || exit 0
                COUNT=$(find "$DIR" -type f -mmin +60 | wc -l)
                if [ "$COUNT" -gt 0 ]; then
                  find "$DIR" -type f -mmin +60 -delete
                  find "$DIR" -mindepth 1 -type d -empty -delete
                  echo "jellyfin-transcode-cleanup: $COUNT Dateien gelöscht"
                fi
              '';
              User = "root";
            };
          };

          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              intel-media-driver
              intel-compute-runtime
              ocl-icd
            ];
          };

          users.users.jellyfin.extraGroups = [
            "video"
            "render"
            "media"
          ];

          systemd.services.jellyfin.environment = {
            LIBVA_DRIVER_NAME = "iHD";
            LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
            VDPAU_DRIVER = "va_gl";
            OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
          };

          environment.systemPackages = with pkgs; [
            libva-utils
            intel-gpu-tools
          ];
        }
        (factory.mkStreamer {
          inherit config;
          name = "jellyfin";
          port = portJellyfin;
          useGPU = true;
          manageIngress = false;
          memoryPolicy = memory.jellyfin { };
          persistDirs = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
          ];
          readWritePaths = [
            "/var/lib/jellyfin"
            "/var/cache/jellyfin"
            "/run/jellyfin-transcode"
            "/mnt/fast_pool/cache/jellyfin"
            "/mnt/fast_pool/metadata/jellyfin"
            "/data/downloads"
          ];
          readOnlyPaths = [
            "/data/media"
            "${pkgs.intel-media-driver}/lib"
            "${pkgs.intel-compute-runtime}/lib"
            "/run/opengl-driver"
          ];
          extraSystemd = {
            IPAddressAllow = lib.mkForce [
              "127.0.0.0/8"
              "10.0.0.0/8"
              "192.168.0.0/16"
              "100.64.0.0/10"
            ];
            IPAddressDeny = lib.mkForce "any";
          };
        })
      ]
    ))

    (lib.mkIf cfgJellyseerr.enable (
      lib.mkMerge [
        {
          services.seerr = {
            enable = true;
            port = portJellyseerr;
            openFirewall = false;
          };
        }
        (factory.mkService {
          inherit config;
          name = "seerr";
          port = portJellyseerr;
          mode = "sso";
          persistDirs = [ "/var/lib/seerr" ];
          readWritePaths = [ "/var/lib/seerr" ];
        })
      ]
    ))
  ];
}
