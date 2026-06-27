# ---
# meta:
#   id: NIXH-50-MED-006
#   layer: 3
#   role: module
#   purpose: Navidrome Music-Server mit Pocket-ID OIDC-SSO via EnvironmentFile
#   lib:
#     - lib/service-factory.nix
#     - lib/memory-policy.nix
#   services:
#     - navidrome
#   tags:
#     - media
#     - navidrome
#     - music
#     - oidc
# ---
#
# OIDC-Setup (einmalig nach erstem Start):
#   1. Pocket-ID → Applications → New → Name: "Navidrome"
#      Callback URL: https://music.DOMAIN/auth/oidc/callback
#   2. client_id + client_secret in profile.local.nix:
#        secrets.oidc.navidrome = { clientId = "…"; clientSecret = "…"; };
#   3. nixos-rebuild switch → /var/lib/secrets/navidrome-oidc.env erscheint
#   4. Ein weiterer rebuild aktiviert OIDC-Login im UI
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.navidrome;
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
  domain = config.my.configs.identity.domain;
  port = config.my.ports.navidrome;
  mediaRoot = config.my.services.storage.poolMountPoint;
  storageReady = config.my.services.storage.enable or false;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.navidrome = {
          enable = true;
          settings = {
            Address = "127.0.0.1";
            Port = port;
            DataFolder = "/var/lib/navidrome";
            MusicFolder = lib.mkIf storageReady "${mediaRoot}/music";
            # OIDC public settings — ClientId + ClientSecret + Enabled kommen via EnvironmentFile.
            # Datei /var/lib/secrets/navidrome-oidc.env (wird durch secrets.nix provisioniert):
            #   ND_OIDCENABLED=true
            #   ND_OIDCCLIENTID=navidrome
            #   ND_OIDCCLIENTSECRET=<secret>
            Oidc = {
              DiscoveryUrl = "https://auth.${domain}/.well-known/openid-configuration";
              AutoRegister = true;
              Scopes = "openid profile email";
            };
          };
        };

        # -Prefix: systemd ignoriert fehlende Datei → Navidrome startet ohne OIDC bis Secrets gesetzt
        systemd.services.navidrome.serviceConfig.EnvironmentFile = [
          "-/var/lib/secrets/navidrome-oidc.env"
        ];
      }

      (factory.mkService {
        inherit config;
        name = "navidrome";
        inherit port;
        mode = "sso";
        persistDirs = [ "/var/lib/navidrome" ];
        readWritePaths = [
          "/var/lib/navidrome"
        ]
        ++ lib.optionals storageReady [ "${mediaRoot}/music" ];
        memoryPolicy = memory.navidrome { };
      })

      (lib.mkIf storageReady {
        systemd.tmpfiles.rules = [ "d ${mediaRoot}/music 0775 navidrome media -" ];
      })
    ]
  );
}
