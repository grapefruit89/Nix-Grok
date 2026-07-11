{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgJellyfin = config.my.services.jellyfin;
  cfgSabnzbd = config.my.services.sabnzbd;
  arrProvision = pkgs.callPackage ../../../packages/arr-provision { };

  targetLang = config.my.configs.locale.language;
  targetLocale = config.my.configs.locale.default;

  anyEnabled = cfgJellyfin.enable || cfgSabnzbd.enable;

  defaultCategories = [
    {
      name = "tv";
      dir = "tv";
      newzbin = "tv";
      order = 2;
      pp = "";
      script = "Default";
      priority = -100;
    }
    {
      name = "movies";
      dir = "movies";
      newzbin = "movies";
      order = 1;
      pp = "";
      script = "Default";
      priority = -100;
    }
    {
      name = "audiobooks";
      dir = "audiobooks";
      newzbin = "audiobooks";
      order = 3;
      pp = "";
      script = "Default";
      priority = -100;
    }
    {
      name = "music";
      dir = "music";
      newzbin = "music";
      order = 5;
      pp = "";
      script = "Default";
      priority = -100;
    }
    {
      name = "scenecart";
      dir = "scenecart";
      newzbin = "sceneCart";
      order = 4;
      pp = "";
      script = "Default";
      priority = -100;
    }
  ];

  mkCategoryIni =
    cats:
    lib.concatMapStringsSep "\n" (cat: ''
      [[${cat.name}]]
      name = ${cat.name}
      order = ${toString cat.order}
      pp = ${cat.pp}
      script = ${cat.script}
      dir = ${cat.dir}
      newzbin = ${cat.newzbin}
      priority = ${toString cat.priority}
    '') cats;

  categoriesIniBlock = "[categories]\n${mkCategoryIni defaultCategories}";

in
{
  options.my.media.sync.locale = {
    enable = lib.mkEnableOption "Jellyfin + SABnzbd Locale-Sync aus Nix SSoT";
    sabnzbd.categories = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            dir = lib.mkOption { type = lib.types.str; };
            newzbin = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            order = lib.mkOption {
              type = lib.types.int;
              default = 0;
            };
            pp = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            script = lib.mkOption {
              type = lib.types.str;
              default = "Default";
            };
            priority = lib.mkOption {
              type = lib.types.int;
              default = -100;
            };
          };
        }
      );
      default = defaultCategories;
      description = "SABnzbd-Kategorien — deklarativ definiert, per Sync eingepflegt.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf anyEnabled {
      my.media.sync.locale.enable = lib.mkDefault true;
    })
    (lib.mkIf (anyEnabled && config.my.media.sync.locale.enable) {
      systemd.services.arr-sync-locale = {
        description = "Declarative Media Locale Sync (Jellyfin + SABnzbd)";
        after =
          lib.optional cfgJellyfin.enable "jellyfin.service"
          ++ lib.optional cfgSabnzbd.enable "sabnzbd.service";
        wants =
          lib.optional cfgJellyfin.enable "jellyfin.service"
          ++ lib.optional cfgSabnzbd.enable "sabnzbd.service";
        wantedBy = [ "multi-user.target" ];

        startLimitIntervalSec = 300;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 3;
        };

        environment = {
          TARGET_LANG = targetLang;
          TARGET_LOCALE = targetLocale;
          CATEGORIES_INI = categoriesIniBlock;
          SAB_KEY_FILE = "/var/lib/secrets/sabnzbd_api_key";
          SYNC_JELLYFIN = if cfgJellyfin.enable then "1" else "0";
          SYNC_SABNZBD = if cfgSabnzbd.enable then "1" else "0";
        };

        script = lib.getExe arrProvision.localeSync;
      };
    })
  ];
}
