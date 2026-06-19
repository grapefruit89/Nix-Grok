/*
  ---
  id: recyclarr
  upstream_repo: "recyclarr/recyclarr"
  ---
*/

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.recyclarr;
  dataDir = "/data/state/recyclarr";
in
{
  options.my.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr (TRaSH-Guides sync)";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 root root -"
    ];

    systemd.services.recyclarr-sync = {
      description = "Recyclarr TRaSH-Guides Sync";
      after = [ "network-online.target" "sonarr.service" "radarr.service" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.recyclarr pkgs.envsubst ];
      preStart = ''
        export RECYCLARR_APP_DATA="${dataDir}"
        RADARR_API_KEY=$(cat "''${CREDENTIALS_DIRECTORY}/RADARR_API_KEY")
        SONARR_API_KEY=$(cat "''${CREDENTIALS_DIRECTORY}/SONARR_API_KEY")
        
        # Inject Recyclarr YAML configuration declaratively
        cat <<EOF > ${dataDir}/recyclarr.yml
radarr:
  nixos-radarr:
    base_url: http://127.0.0.1:${toString config.my.ports.radarr}
    api_key: $RADARR_API_KEY
    quality_definition:
      type: movie
      preferred_ratio: 0.5
    quality_profiles:
      - name: 1080p_Deutsch
        reset_unmatched_scores: true
    custom_formats:
      - trash_ids:
          - 496f355514737f7d83bf7aa4d24f8169 # German
          - 5e11ed42a77f0a6cd250085d56b006c6 # German/English MULTI
        quality_profiles:
          - name: 1080p_Deutsch
            score: 1000
      - trash_ids:
          - 2f22d89048b01681dde8afe203bf2e95 # English Only
        quality_profiles:
          - name: 1080p_Deutsch
            score: 0
      - trash_ids:
          - 104b901dd78e3dbd4ab5cb14f09d84c1 # Unknown/Foreign Language
        quality_profiles:
          - name: 1080p_Deutsch
            score: -10000 # BLOCK
      - trash_ids:
          - 839bea857ed2c0a8e084f3cbdbd65ecb # x265 (HD)
          - 66c3080ffb82ee2cf82902ea64a2a16c # AV1
        quality_profiles:
          - name: 1080p_Deutsch
            score: 100 # Bevorzuge effiziente Codecs für FireTV
EOF
      '';
      script = ''
        export RECYCLARR_APP_DATA="${dataDir}"
        recyclarr sync
      '';
      serviceConfig = {
        LoadCredential = [
          "RADARR_API_KEY:/home/moritz/secrets/radarr_api_key"
          "SONARR_API_KEY:/home/moritz/secrets/sonarr_api_key"
        ];
        OOMScoreAdjust = 500;
        Type = "oneshot";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ dataDir ];
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr Sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
