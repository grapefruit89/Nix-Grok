# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Recyclarr — TRaSH Guides Custom Formats / Quality Profiles
#   tags:
#     - media
#     - recyclarr
#     - trash-guides
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.recyclarr;
  ports = config.my.ports;
  secretsDir = "/var/lib/secrets";

  # WEB-only 1080p: kein Bluray (typ. 10–20 GB). Ziel ~6 GB/100 min via preferred.
  # min ≤ preferred ≤ max: bevorzugt ~50 MB/min, Fallback bis 75 MB/min wenn nichts Kleineres existiert.
  web1080pSizeLimits = [
    {
      name = "WEBDL-1080p";
      min = 12.5;
      preferred = 50;
      max = 75;
    }
    {
      name = "WEBRip-1080p";
      min = 12.5;
      preferred = 50;
      max = 75;
    }
  ];
  movieQualityDefinition = {
    type = "movie";
    qualities = web1080pSizeLimits;
  };
  seriesQualityDefinition = {
    type = "series";
    qualities = web1080pSizeLimits;
  };

  # Zwei Profile: Deutsch-primär (min 10k → nur German/German-DL passiert),
  # Englisch-sekundär (min 0 → pure English passiert, German/andere abgestraft).
  # WEB-only (kein Bluray). Qualitäten gemergt → Sprach-Upgrades ohne Quality-Blocker.
  germanProfile = {
    name = "German 1080p HEVC";
    min_format_score = 10000;
    upgrade = {
      allowed = true;
      until_quality = "1080p";
      until_score = 35000;
    };
    quality_sort = "top";
    qualities = [
      {
        name = "1080p";
        qualities = [
          "WEBDL-1080p"
          "WEBRip-1080p"
        ];
      }
    ];
    reset_unmatched_scores.enabled = true;
  };

  englishProfile = {
    name = "English 1080p HEVC";
    min_format_score = 0;
    upgrade = {
      allowed = true;
      until_quality = "1080p";
      until_score = 10000;
    };
    quality_sort = "top";
    qualities = [
      {
        name = "1080p";
        qualities = [
          "WEBDL-1080p"
          "WEBRip-1080p"
        ];
      }
    ];
    reset_unmatched_scores.enabled = true;
  };

  profileNames = [
    "German 1080p HEVC"
    "English 1080p HEVC"
  ];

  mkBlock =
    trash_id:
    lib.map (name: {
      inherit name;
      score = -35000;
    }) profileNames;

  mkRepack =
    trash_id: score:
    lib.map (name: {
      inherit name;
      score = score;
    }) profileNames;

  radarrLqAndRepack = [
    {
      trash_ids = [ "6aad77771dabe9d3e9d7be86f310b867" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 11000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      trash_ids = [ "ed38b889b31be83fda192888e2286d83" ];
      assign_scores_to = mkBlock "br-disk";
    }
    {
      trash_ids = [ "90a6f9a284dff5103f6346090e6280c8" ];
      assign_scores_to = mkBlock "lq";
    }
    {
      trash_ids = [ "e204b80c87be9497a8a6eaff48f72905" ];
      assign_scores_to = mkBlock "lq-rt";
    }
    {
      trash_ids = [ "263943bc5d99550c68aad0c4278ba1c7" ];
      assign_scores_to = mkBlock "german-lq";
    }
    {
      trash_ids = [ "a826ee9e46607bc61795c85a6f2b1279" ];
      assign_scores_to = mkBlock "german-lq-rt";
    }
    {
      trash_ids = [ "03c430f326f10a27a9739b8bc83c30e4" ];
      assign_scores_to = mkBlock "german-micro";
    }
    {
      trash_ids = [ "b8cd450cbfa689c0259a01d9e29ba3d6" ];
      assign_scores_to = mkBlock "3d";
    }
    {
      trash_ids = [ "c465ccc73923871b3eb1802042331306" ];
      assign_scores_to = mkBlock "linemic";
    }
    {
      trash_ids = [ "0a3f082873eb454bde444150b70253cc" ];
      assign_scores_to = mkBlock "extras";
    }
    {
      trash_ids = [ "cae4ca30163749b891686f95532519bd" ];
      assign_scores_to = mkBlock "av1";
    }
    {
      trash_ids = [ "bfd8eb01832d646a0a89c4deb46f8564" ];
      assign_scores_to = mkBlock "upscaled";
    }
    {
      trash_ids = [ "e7718d7a3ce595f289bfee26adc178f5" ];
      assign_scores_to = mkRepack "repack" 5;
    }
    {
      trash_ids = [ "ae43b294509409a6a13919dedd4764c4" ];
      assign_scores_to = mkRepack "repack2" 6;
    }
    {
      trash_ids = [ "5caaaa1c08c1742aa4342d8c4cc463f2" ];
      assign_scores_to = mkRepack "repack3" 7;
    }
  ];

  sonarrLqAndRepack = [
    {
      trash_ids = [ "c5dd0fd675f85487ad5bdf97159180bd" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 11000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      trash_ids = [ "85c61753df5da1fb2aab6f2a47426b09" ];
      assign_scores_to = mkBlock "br-disk";
    }
    {
      trash_ids = [ "9c11cd3f07101cdba90a2d81cf0e56b4" ];
      assign_scores_to = mkBlock "lq";
    }
    {
      trash_ids = [ "e2315f990da2e2cbfc9fa5b7a6fcfe48" ];
      assign_scores_to = mkBlock "lq-rt";
    }
    {
      trash_ids = [ "a6a6c33d057406aaad978a6902823c35" ];
      assign_scores_to = mkBlock "german-lq";
    }
    {
      trash_ids = [ "d80c9f7cd2aad50271f1bd4e53125778" ];
      assign_scores_to = mkBlock "german-lq-rt";
    }
    {
      trash_ids = [ "237eda4ef550a97da2c9d87b437e500b" ];
      assign_scores_to = mkBlock "german-micro";
    }
    {
      trash_ids = [ "fbcb31d8dabd2a319072b84fc0b7249c" ];
      assign_scores_to = mkBlock "extras";
    }
    {
      trash_ids = [ "15a05bc7c1a36e2b57fd628f8977e2fc" ];
      assign_scores_to = mkBlock "av1";
    }
    {
      trash_ids = [ "23297a736ca77c0fc8e70f8edd7ee56c" ];
      assign_scores_to = mkBlock "upscaled";
    }
    {
      trash_ids = [ "ec8fa7296b64e8cd390a1600981f3923" ];
      assign_scores_to = mkRepack "repack" 5;
    }
    {
      trash_ids = [ "eb3d5cc0a2be0db205fb823640db6a3c" ];
      assign_scores_to = mkRepack "repack2" 6;
    }
    {
      trash_ids = [ "44e7c4de10ae50265753082e5dc76047" ];
      assign_scores_to = mkRepack "repack3" 7;
    }
  ];
  # TRaSH Custom Formats für Radarr (trash_ids Radarr-spezifisch)
  radarrCustomFormats = [
    {
      # German DL: German+Originalsprache gleichzeitig — Kernbedingung für German-Profil
      trash_ids = [ "f845be10da4f442654c13e1f2c3d6cd5" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 11000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      # German: nur Deutsch (kein DL) — z.B. deutsche Originalfilme
      trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 10000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      # Language: Not English — reverse scoring für English-only Profil
      trash_ids = [ "0dc8aec3bd1c47cd6c40c46ecd27e846" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 0;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      # Not German or English: Hindi/andere Sprachen — hard block in beiden Profilen
      trash_ids = [ "4eadb75fb23d09dfc0a8e3f687e72287" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = -35000;
        }
        {
          name = "English 1080p HEVC";
          score = -35000;
        }
      ];
    }
    {
      # x265/HEVC: bevorzuge H.265-Encodes für kleinere Dateigröße
      trash_ids = [ "9170d55c319f4fe40da8711ba9d8050d" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 500;
        }
        {
          name = "English 1080p HEVC";
          score = 500;
        }
      ];
    }
    {
      # German 1080p Booster: zusätzlicher Boost für German-DL 1080p-Releases
      trash_ids = [ "3bc8df3a71baaac60a31ef696ea72d36" ];
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 650;
        }
      ];
    }
  ];

  # TRaSH Custom Formats für Sonarr (trash_ids Sonarr-spezifisch — nicht kompatibel mit Radarr)
  sonarrCustomFormats = [
    {
      trash_ids = [ "ed51973a811f51985f14e2f6f290e47a" ]; # German DL
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 11000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      trash_ids = [ "8a9fcdbb445f2add0505926df3bb7b8a" ]; # German
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 10000;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      trash_ids = [ "69aa1e159f97d860440b04cd6d590c4f" ]; # Language: Not English
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 0;
        }
        {
          name = "English 1080p HEVC";
          score = -10000;
        }
      ];
    }
    {
      trash_ids = [ "133589380b89f8f8394320901529bac1" ]; # Not German or English
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = -35000;
        }
        {
          name = "English 1080p HEVC";
          score = -35000;
        }
      ];
    }
    {
      trash_ids = [ "c9eafd50846d299b862ca9bb6ea91950" ]; # x265
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 500;
        }
        {
          name = "English 1080p HEVC";
          score = 500;
        }
      ];
    }
    {
      trash_ids = [ "9aa0ca0d2d66b6f6ee51fc630f46cf6f" ]; # German 1080p Booster
      assign_scores_to = [
        {
          name = "German 1080p HEVC";
          score = 650;
        }
      ];
    }
  ];
in
{
  options.my.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr TRaSH Guides sync for Sonarr/Radarr";
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar schedule for recyclarr sync.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.services.sonarr.enable || config.my.services.radarr.enable;
        message = "my.services.recyclarr.enable requires sonarr and/or radarr.";
      }
    ];

    services.recyclarr = {
      enable = true;
      schedule = cfg.schedule;
      configuration = lib.mkMerge [
        (lib.mkIf config.my.services.sonarr.enable {
          sonarr.sonarr = {
            base_url = "http://127.0.0.1:${toString ports.sonarr}";
            api_key._secret = "${secretsDir}/sonarr_api_key";
            delete_old_custom_formats = true;
            quality_definition = seriesQualityDefinition;
            quality_profiles = [
              germanProfile
              englishProfile
            ];
            custom_formats = sonarrCustomFormats ++ sonarrLqAndRepack;
          };
        })
        (lib.mkIf config.my.services.radarr.enable {
          radarr.radarr = {
            base_url = "http://127.0.0.1:${toString ports.radarr}";
            api_key._secret = "${secretsDir}/radarr_api_key";
            delete_old_custom_formats = true;
            quality_definition = movieQualityDefinition;
            quality_profiles = [
              germanProfile
              englishProfile
            ];
            custom_formats = radarrCustomFormats ++ radarrLqAndRepack;
          };
        })
      ];
    };
  };
}
