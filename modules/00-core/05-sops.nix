# ---
# meta:
#   id: NIXH-05-MOD-005
#   layer: 3
#   role: module
#   purpose: SOPS-Migration (Stufe 9+) — Schema + Kategorien nach mynixos-v5
#   docs:
#     - docs/adr/006-sops-migration-path.md
#   tags:
#     - sops
#     - secrets
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.sops;

  defaultCategories = {
    infra = [
      "cloudflare_token"
      "netbird_setup_key"
      "restic_password"
      "privado_private_key"
      "gatus_ssh_key"
    ];
    media = [
      "prowlarr_api_key"
      "sonarr_api_key"
      "radarr_api_key"
      "readarr_api_key"
      "sabnzbd_api_key"
      "scenenzbs_api_key"
      "sabnzbd_usenet_user"
      "sabnzbd_usenet_password"
      "vaultwarden_admin_token"
      "vaultwarden_env"
    ];
  };

  defaultAllKeys = defaultCategories.infra ++ defaultCategories.media;
in
{
  options.my.sops = {
    enable = lib.mkEnableOption "SOPS secrets (ersetzt secrets-provision ab Stufe 9)";
    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets";
      description = "Verzeichnis mit infra.yaml / media.yaml (nicht im Git-Index).";
    };
    categories = lib.mkOption {
      type = lib.types.submodule {
        options = {
          infra = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = defaultCategories.infra;
          };
          media = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = defaultCategories.media;
          };
        };
      };
      default = { };
      description = "Secret-Keys pro SOPS-Datei (Blast-Radius minimieren).";
    };
    schema = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.genAttrs defaultAllKeys (_: "");
      description = "Erlaubte SOPS-Keys — unbekannte Einträge in sops.secrets erzeugen eine Warnung.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
      let
        infraKeys = cfg.categories.infra;
        mediaKeys = cfg.categories.media;
        allKeys = infraKeys ++ mediaKeys;

        sopsEntries = lib.genAttrs allKeys (name: {
          sopsFile =
            if lib.elem name infraKeys then cfg.secretsDir + "/infra.yaml" else cfg.secretsDir + "/media.yaml";
          neededForUsers = lib.hasSuffix "_password" name;
        });

        unknownKeys =
          let
            defined = lib.attrNames (config.sops.secrets or { });
          in
          lib.filter (k: !lib.elem k allKeys) defined;
      in
      {
        warnings =
          lib.optional (unknownKeys != [ ])
            "[SOPS-SCHEMA] Unbekannte Keys in sops.secrets: ${lib.concatStringsSep ", " unknownKeys}. In my.sops.categories registrieren.";

        assertions = [
          {
            assertion = builtins.pathExists (cfg.secretsDir + "/infra.yaml");
            message = "[SOPS] ${cfg.secretsDir}/infra.yaml fehlt — vor Stufe 9 anlegen (sops encrypt).";
          }
          {
            assertion = builtins.pathExists (cfg.secretsDir + "/media.yaml");
            message = "[SOPS] ${cfg.secretsDir}/media.yaml fehlt — vor Stufe 9 anlegen (sops encrypt).";
          }
          {
            assertion = (lib.length (lib.unique allKeys)) == (lib.length allKeys);
            message = "[SOPS-SCHEMA] Doppelte Keys über infra/media-Kategorien hinweg.";
          }
        ];

        sops = {
          defaultSopsFile = cfg.secretsDir + "/secrets.yaml";
          age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          secrets = sopsEntries;
        };

        systemd.services.sops-recovery-validation = {
          description = "SOPS file presence check";
          serviceConfig.Type = "oneshot";
          script = ''
            set -euo pipefail
            for f in ${cfg.secretsDir}/infra.yaml ${cfg.secretsDir}/media.yaml; do
              if [ ! -f "$f" ]; then
                echo "[SOPS] missing: $f"
                exit 1
              fi
            done
          '';
        };

        systemd.timers.sops-recovery-validation = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "weekly";
            Persistent = true;
          };
        };
      }
    ))
  ];
}
