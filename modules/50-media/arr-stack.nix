{ config, lib, pkgs, ... }:

let
  cfgSonarr = config.my.services.sonarr;
  cfgRadarr = config.my.services.radarr;
  cfgProwlarr = config.my.services.prowlarr;

  ports = config.my.ports;
  arrHelper = import ./arr-helper.nix { inherit config lib pkgs; };

in
{
  config = lib.mkMerge [

    (lib.mkIf cfgSonarr.enable (arrHelper.mkArrService {
      name = "sonarr";
      port = ports.sonarr;
      dataDir = "/data/state/sonarr";
      uid = 989;
      gid = 989;
      apiSetupScript = ''
        PROFILE_EXISTS=$(curl -s "$API_URL/releaseprofile?apiKey=$API_KEY" | jq -e '.[] | select(.name == "Hardware Codec Optimization (HEVC/x265)") | .id' > /dev/null && echo "true" || echo "false")
        if [ "$PROFILE_EXISTS" = "false" ]; then
          curl -s -X POST "$API_URL/releaseprofile?apiKey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"name": "Hardware Codec Optimization (HEVC/x265)", "enabled": true, "required": [], "ignored": [], "indexerId": 0, "tags": [], "preferred": [{"term": "x265", "score": 5000}, {"term": "HEVC", "score": 5000}], "includePreferredWhenRenaming": false}'
        fi
      '';
    }))


    (lib.mkIf cfgRadarr.enable (arrHelper.mkArrService {
      name = "radarr";
      port = ports.radarr;
      dataDir = "/data/state/radarr";
      uid = 978;
      gid = 978;
    }))


    (lib.mkIf cfgProwlarr.enable (arrHelper.mkArrService {
      name = "prowlarr";
      port = ports.prowlarr;
      dataDir = "/data/state/prowlarr";
      uid = 969;
      gid = 969;
      useVpnKillSwitch = true;
    }))
  ];
}



