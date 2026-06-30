{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgJellyfin = config.my.services.jellyfin;
  cfgSabnzbd = config.my.services.sabnzbd;

  targetLang = config.my.configs.locale.language;
  targetLocale = config.my.configs.locale.default;

  anyEnabled = cfgJellyfin.enable || cfgSabnzbd.enable;

  # SABnzbd-Kategorien: deklarativ in Nix definiert, per Sync in die laufende ini eingepflegt.
  # Format: { name, dir, newzbin, order, pp, script }
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
      script = "";
      priority = -100;
    }
  ];

  # INI-Sektion für SABnzbd-Kategorien generieren (SABnzbd-spezifisches [[name]]-Format)
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

  # Python-Snippet für Jellyfin system.xml Locale-Injection
  jellyfinLocaleScript = pkgs.writeText "jellyfin-locale.py" ''
    import xml.etree.ElementTree as ET
    import sys, os

    path = '/var/lib/jellyfin/config/system.xml'
    lang = '${targetLang}'
    country = '${lib.toUpper (lib.elemAt (lib.splitString "_" targetLocale) 1)}'
    ui_culture = '${lib.replaceStrings [ "_" ] [ "-" ] (lib.removeSuffix ".UTF-8" targetLocale)}'

    if not os.path.exists(path):
        print(f'Jellyfin system.xml nicht gefunden: {path} — überspringen', file=sys.stderr)
        sys.exit(0)

    try:
        ET.register_namespace("", "")
        tree = ET.parse(path)
        root = tree.getroot()
        changes = 0

        for tag, val in [
            ('PreferredMetadataLanguage', lang),
            ('MetadataCountryCode', country),
            ('UICulture', ui_culture),
        ]:
            el = root.find(tag)
            if el is not None and el.text != val:
                el.text = val
                changes += 1

        if changes:
            tree.write(path, encoding='utf-8', xml_declaration=True)
            print(f'Jellyfin system.xml: {changes} Felder gesetzt ({lang}/{country}/{ui_culture})')
        else:
            print(f'Jellyfin system.xml: bereits korrekt ({lang}/{country}/{ui_culture})')
    except Exception as e:
        print(f'Fehler beim Lesen/Schreiben von system.xml: {e}', file=sys.stderr)
        sys.exit(1)
  '';

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

  config = lib.mkIf (anyEnabled && config.my.media.sync.locale.enable) {
    systemd.services.arr-sync-locale = {
      description = "Declarative Media Locale Sync (Jellyfin + SABnzbd)";
      after =
        lib.optional cfgJellyfin.enable "jellyfin.service"
        ++ lib.optional cfgSabnzbd.enable "sabnzbd.service";
      wants =
        lib.optional cfgJellyfin.enable "jellyfin.service"
        ++ lib.optional cfgSabnzbd.enable "sabnzbd.service";
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [
        python3
        coreutils
        gnugrep
        gnused
      ];

      startLimitIntervalSec = 300;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        # Neustart bei Fehlern (z.B. Service noch nicht bereit)
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitBurst = 3;

      };

      environment = {
        TARGET_LANG = targetLang;
        TARGET_LOCALE = targetLocale;
        CATEGORIES_INI = categoriesIniBlock;
        SAB_KEY_FILE = "/var/lib/secrets/sabnzbd_api_key";
      };

      script = ''
        # ── JELLYFIN LOCALE ──────────────────────────────────────────────────
        ${lib.optionalString cfgJellyfin.enable ''
          echo "=== Jellyfin Locale Sync ==="
          ${pkgs.python3}/bin/python3 ${jellyfinLocaleScript}
        ''}

        # ── SABNZBD LOCALE + KATEGORIEN ──────────────────────────────────────
        ${lib.optionalString cfgSabnzbd.enable ''
          echo "=== SABnzbd Locale + Kategorien Sync ==="
          SAB_INI="/var/lib/sabnzbd/sabnzbd.ini"

          # SABnzbd muss mindestens einmal gelaufen sein, damit sabnzbd.ini existiert
          if [ ! -f "$SAB_INI" ]; then
            echo "sabnzbd.ini noch nicht vorhanden — Sync wird übersprungen (SABnzbd noch nicht initialisiert)."
          else
            # Sprache setzen
            if grep -q "^language" "$SAB_INI"; then
              sed -i "s|^language.*|language = $TARGET_LANG|" "$SAB_INI"
            else
              sed -i "1s|^|language = $TARGET_LANG\n|" "$SAB_INI"
            fi
            echo "SABnzbd: Sprache auf $TARGET_LANG gesetzt."

            # API-Key setzen (aus Secret)
            if [ -f "$SAB_KEY_FILE" ]; then
              SAB_KEY=$(cat "$SAB_KEY_FILE")
              for key in api_key nzb_key; do
                if grep -q "^$key" "$SAB_INI"; then
                  sed -i "s|^$key.*|$key = $SAB_KEY|" "$SAB_INI"
                else
                  sed -i "1s|^|$key = $SAB_KEY\n|" "$SAB_INI"
                fi
              done
              echo "SABnzbd: API-Keys gesetzt."
            fi

            # Kategorien: nur einfügen wenn [categories] noch nicht existiert
            if ! grep -q "^\[categories\]" "$SAB_INI"; then
              echo "SABnzbd: Kategorien werden eingefügt..."
              printf '\n%s\n' "$CATEGORIES_INI" >> "$SAB_INI"
              echo "SABnzbd: Kategorien eingefügt. Neustart zum Einlesen..."
              systemctl restart sabnzbd.service || true
            else
              echo "SABnzbd: Kategorien bereits vorhanden — übersprungen."
            fi
          fi
        ''}

        echo "Locale-Sync abgeschlossen."
      '';
    };
  };
}
