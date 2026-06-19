# arr-helper.nix
# Shared helper to generate standardized *Arr services.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  vpnKillSwitchAttrs = import ../../lib/vpn-killswitch.nix {
    inherit lib;
    privadoEnabled = config.my.services.privado-vpn.enable or false;
  };
in
{
  mkArrService =
    {
      name,
      port,
      dataDir,
      uid,
      gid,
      useVpnKillSwitch ? false,
      apiSetupScript ? "",
    }:
    {
      services.${name} = {
        enable = true;
        openFirewall = false;
        inherit dataDir;
      };

      users.groups.${name} = {
        gid = lib.mkDefault gid;
      };
      users.users.${name} = {
        uid = lib.mkDefault uid;
        group = name;
        isSystemUser = true;
        extraGroups = [ "media" ];
      };

      systemd.services.${name} = lib.mkMerge [
        (lib.mkIf useVpnKillSwitch vpnKillSwitchAttrs)
        {
          preStart = lib.mkBefore ''
                      if [ ! -f ${dataDir}/config.xml ]; then
                        mkdir -p ${dataDir}
                        cat > ${dataDir}/config.xml <<EOF
            <Config>
              <BindAddress>127.0.0.1</BindAddress>
              <PostgresUser>${name}</PostgresUser>
              <PostgresPassword>nixgrok</PostgresPassword>
              <PostgresPort>5432</PostgresPort>
              <PostgresHost>127.0.0.1</PostgresHost>
              <PostgresMainDb>${name}-main</PostgresMainDb>
              <PostgresLogDb>${name}-log</PostgresLogDb>
            </Config>
            EOF
                      else
                        ${pkgs.gnused}/bin/sed -i -e 's|<BindAddress>.*</BindAddress>|<BindAddress>127.0.0.1</BindAddress>|g' ${dataDir}/config.xml
                        if ! grep -q "<BindAddress>" ${dataDir}/config.xml; then
                          ${pkgs.gnused}/bin/sed -i -e 's|</Config>|<BindAddress>127.0.0.1</BindAddress></Config>|g' ${dataDir}/config.xml
                        fi
                        # Add Postgres settings if missing in existing config
                        if ! grep -q "<PostgresHost>" ${dataDir}/config.xml; then
                          ${pkgs.gnused}/bin/sed -i -e 's|</Config>|<PostgresUser>${name}</PostgresUser><PostgresPassword>nixgrok</PostgresPassword><PostgresPort>5432</PostgresPort><PostgresHost>127.0.0.1</PostgresHost><PostgresMainDb>${name}-main</PostgresMainDb><PostgresLogDb>${name}-log</PostgresLogDb></Config>|g' ${dataDir}/config.xml
                        fi
                      fi
          '';
          serviceConfig = {
            MemoryMax = "2G";
            OOMScoreAdjust = 500;
            ProtectSystem = lib.mkForce "strict";
            ProtectHome = lib.mkForce true;
            PrivateTmp = lib.mkForce true;
            PrivateDevices = lib.mkForce true;
            NoNewPrivileges = lib.mkForce true;
            UMask = lib.mkForce "0002";
            ReadWritePaths = [
              dataDir
              "/data/media"
              "/data/downloads"
            ];
          };
        }
      ];

      services.caddy.virtualHosts."${name}.${config.my.configs.identity.domain}" = {
        extraConfig = caddy.proxySso port;
      };

      systemd.services."${name}-configurator" = lib.mkIf (apiSetupScript != "") {
        description = "Idempotent API Configurator for ${name}";
        wantedBy = [ "multi-user.target" ];
        requires = [ "${name}.service" ];
        after = [ "${name}.service" ];

        path = with pkgs; [
          curl
          jq
          gnugrep
        ];

        script = ''
          set -euo pipefail

          CONFIG_XML="${dataDir}/config.xml"
          API_URL="http://localhost:${toString port}/api/v3"

          echo "Warte auf config.xml..."
          while [ ! -f "$CONFIG_XML" ]; do sleep 1; done

          API_KEY=$(grep -oP '(?<=<ApiKey>)[^<]+' "$CONFIG_XML")

          echo "Warte auf API..."
          while ! curl -s --fail "$API_URL/system/status?apiKey=$API_KEY" > /dev/null; do
            sleep 2
          done

          # Führe app-spezifisches Setup aus
          ${apiSetupScript}
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
    };
}
