{
  lib,
  pkgs,
  ...
}:
let
  p = import ./profile.nix;
  local = if builtins.pathExists ./profile.local.nix then import ./profile.local.nix else { };
  secretsDir = p.secrets.dir;
  dk = p.secrets.devKeys;
  mk = dk.media or { };

  # ── *arr + Media-Apps ────────────────────────────────────────────────────────
  arrKeys = {
    prowlarr =
      mk.prowlarr.apiKey or (throw "devKeys.media.prowlarr.apiKey in profile.local.nix setzen");
    sonarr = mk.sonarr.apiKey or (throw "devKeys.media.sonarr.apiKey in profile.local.nix setzen");
    radarr = mk.radarr.apiKey or (throw "devKeys.media.radarr.apiKey in profile.local.nix setzen");
    sabnzbd = mk.sabnzbd.apiKey or (throw "devKeys.media.sabnzbd.apiKey in profile.local.nix setzen");
    lidarr = mk.lidarr.apiKey or "";
    readarr = mk.readarr.apiKey or "";
    jellyfin = mk.jellyfin.apiKey or "";
    jellyseerr = mk.jellyseerr.apiKey or "";
  };

  # ── Indexer ──────────────────────────────────────────────────────────────────
  sceneNzbsKey =
    mk.scenenzbs.apiKey or (throw "devKeys.media.scenenzbs.apiKey in profile.local.nix setzen");

  # ── Usenet-Newsserver ────────────────────────────────────────────────────────
  usenet = local.secrets.usenet or { };
  usenetHost = usenet.host or "";
  usenetPort = usenet.port or 563;
  usenetSsl = usenet.ssl or true;
  usenetUser = usenet.username or "";
  usenetPassword = usenet.password or "";
  hasUsenet = usenetUser != "" && usenetPassword != "" && usenetHost != "";

  provisionScript = pkgs.writeShellScript "q958-media-secrets-provision" ''
    set -euo pipefail
    mkdir -p ${secretsDir}

    # ── *arr API Keys (Pflicht) ───────────────────────────────────────────────
    printf '%s' '${arrKeys.prowlarr}'  > ${secretsDir}/prowlarr_api_key
    printf '%s' '${arrKeys.sonarr}'    > ${secretsDir}/sonarr_api_key
    printf '%s' '${arrKeys.radarr}'    > ${secretsDir}/radarr_api_key
    printf '%s' '${arrKeys.sabnzbd}'   > ${secretsDir}/sabnzbd_api_key
    chmod 600 ${secretsDir}/prowlarr_api_key ${secretsDir}/sonarr_api_key \
              ${secretsDir}/radarr_api_key   ${secretsDir}/sabnzbd_api_key

    # ── *arr EnvironmentFiles (APPNAME__AUTH__APIKEY) ────────────────────────
    # arr-helper.nix lädt diese via EnvironmentFile= direkt in systemd;
    # ersetzt config.xml-Injection in sync-script.sh
    printf 'PROWLARR__AUTH__APIKEY=%s\n' '${arrKeys.prowlarr}' > ${secretsDir}/prowlarr.env
    printf 'SONARR__AUTH__APIKEY=%s\n'   '${arrKeys.sonarr}'   > ${secretsDir}/sonarr.env
    printf 'RADARR__AUTH__APIKEY=%s\n'   '${arrKeys.radarr}'   > ${secretsDir}/radarr.env
    chmod 600 ${secretsDir}/prowlarr.env ${secretsDir}/sonarr.env ${secretsDir}/radarr.env
    ${lib.optionalString (arrKeys.lidarr != "") ''
      printf 'LIDARR__AUTH__APIKEY=%s\n' '${arrKeys.lidarr}' > ${secretsDir}/lidarr.env
      chmod 600 ${secretsDir}/lidarr.env
    ''}
    ${lib.optionalString (arrKeys.readarr != "") ''
      printf 'READARR__AUTH__APIKEY=%s\n' '${arrKeys.readarr}' > ${secretsDir}/readarr.env
      chmod 600 ${secretsDir}/readarr.env
    ''}

    # ── Indexer ───────────────────────────────────────────────────────────────
    printf '%s' '${sceneNzbsKey}' > ${secretsDir}/scenenzbs_api_key
    chmod 600 ${secretsDir}/scenenzbs_api_key

    # ── Optionale *arr / Media-App Keys ──────────────────────────────────────
    ${lib.optionalString (arrKeys.lidarr != "") ''
      printf '%s' '${arrKeys.lidarr}' > ${secretsDir}/lidarr_api_key
      chmod 600 ${secretsDir}/lidarr_api_key
    ''}
    ${lib.optionalString (arrKeys.readarr != "") ''
      printf '%s' '${arrKeys.readarr}' > ${secretsDir}/readarr_api_key
      chmod 600 ${secretsDir}/readarr_api_key
    ''}
    ${lib.optionalString (arrKeys.jellyfin != "") ''
      printf '%s' '${arrKeys.jellyfin}' > ${secretsDir}/jellyfin_api_key
      chmod 600 ${secretsDir}/jellyfin_api_key
    ''}
    ${lib.optionalString (arrKeys.jellyseerr != "") ''
      printf '%s' '${arrKeys.jellyseerr}' > ${secretsDir}/jellyseerr_api_key
      chmod 600 ${secretsDir}/jellyseerr_api_key
    ''}

    # ── Usenet Newsserver-Zugangsdaten ───────────────────────────────────────
    ${lib.optionalString hasUsenet ''
            printf '%s' '${usenetUser}'     > ${secretsDir}/usenet_username
            printf '%s' '${usenetPassword}' > ${secretsDir}/usenet_password
            cat > ${secretsDir}/usenet.env <<'USENETEOF'
      USENET_HOST=${usenetHost}
      USENET_PORT=${toString usenetPort}
      USENET_SSL=${if usenetSsl then "true" else "false"}
      USENET_USER=${usenetUser}
      USENET_PASSWORD=${usenetPassword}
      USENETEOF
            chmod 600 ${secretsDir}/usenet_username ${secretsDir}/usenet_password \
                      ${secretsDir}/usenet.env
    ''}
  '';
in
{
  system.activationScripts.q958MediaSecretsProvision = {
    text = builtins.readFile provisionScript;
    deps = [ "q958SecretsProvision" ];
  };
}
