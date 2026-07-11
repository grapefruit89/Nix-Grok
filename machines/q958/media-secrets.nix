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

  # Profile values — CHANGE_ME / short keys are resolved at activation time (preserve or auto-generate).
  arrKeys = {
    prowlarr = mk.prowlarr.apiKey or "CHANGE_ME";
    sonarr = mk.sonarr.apiKey or "CHANGE_ME";
    radarr = mk.radarr.apiKey or "CHANGE_ME";
    sabnzbd = mk.sabnzbd.apiKey or "CHANGE_ME";
    lidarr = mk.lidarr.apiKey or "";
    readarr = mk.readarr.apiKey or "";
    jellyfin = mk.jellyfin.apiKey or "";
    jellyseerr = mk.jellyseerr.apiKey or "";
    jellyfinAdminPassword = mk.jellyfin.adminPassword or "";
  };

  treasureMapsKey = mk.treasuremaps.apiKey or "CHANGE_ME";

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

    is_placeholder() {
      local val="''${1:-}"
      [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]
    }

    valid_api_key() {
      local key
      key=$(tr -d ' \n\r\t-' < "$1" 2>/dev/null || true)
      local len=''${#key}
      [ "$len" -ge 20 ] && [ "$len" -le 32 ] && printf '%s' "$key" | grep -qE '^[a-zA-Z0-9]+$'
    }

    resolve_api_key() {
      local profile_val="$1"
      local key_file="$2"
      local key=""
      if ! is_placeholder "$profile_val" && valid_api_key <(printf '%s' "$profile_val"); then
        key=$(tr -d ' \n\r\t-' < <(printf '%s' "$profile_val"))
      elif [ -s "$key_file" ] && valid_api_key "$key_file"; then
        key=$(tr -d ' \n\r\t-' < "$key_file")
      else
        key=$(${pkgs.openssl}/bin/openssl rand -hex 16)
      fi
      printf '%s' "$key" > "$key_file"
      chmod 600 "$key_file"
      printf '%s' "$key"
    }

    resolve_password() {
      local profile_val="$1"
      local key_file="$2"
      local min_len="''${3:-12}"
      local pw=""
      if [ -n "$profile_val" ] && [ "$profile_val" != "CHANGE_ME" ] && [ "''${#profile_val}" -ge "$min_len" ]; then
        pw="$profile_val"
      elif [ -s "$key_file" ] && [ "$(wc -c < "$key_file")" -ge "$min_len" ]; then
        pw=$(cat "$key_file")
      else
        pw=$(${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '/+=' | head -c 24)
      fi
      printf '%s' "$pw" > "$key_file"
      chmod 600 "$key_file"
    }

    PROWLARR_KEY=$(resolve_api_key '${arrKeys.prowlarr}' ${secretsDir}/prowlarr_api_key)
    SONARR_KEY=$(resolve_api_key '${arrKeys.sonarr}' ${secretsDir}/sonarr_api_key)
    RADARR_KEY=$(resolve_api_key '${arrKeys.radarr}' ${secretsDir}/radarr_api_key)
    SABNZBD_KEY=$(resolve_api_key '${arrKeys.sabnzbd}' ${secretsDir}/sabnzbd_api_key)
    TREASURE_KEY=$(resolve_api_key '${treasureMapsKey}' ${secretsDir}/treasuremaps_api_key)

    printf 'PROWLARR__AUTH__APIKEY=%s\n' "$PROWLARR_KEY" > ${secretsDir}/prowlarr.env
    printf 'SONARR__AUTH__APIKEY=%s\n'   "$SONARR_KEY"   > ${secretsDir}/sonarr.env
    printf 'RADARR__AUTH__APIKEY=%s\n'   "$RADARR_KEY"   > ${secretsDir}/radarr.env
    chmod 600 ${secretsDir}/prowlarr.env ${secretsDir}/sonarr.env ${secretsDir}/radarr.env

    ${lib.optionalString (arrKeys.lidarr != "") ''
      LIDARR_KEY=$(resolve_api_key '${arrKeys.lidarr}' ${secretsDir}/lidarr_api_key)
      printf 'LIDARR__AUTH__APIKEY=%s\n' "$LIDARR_KEY" > ${secretsDir}/lidarr.env
      chmod 600 ${secretsDir}/lidarr.env
    ''}
    ${lib.optionalString (arrKeys.readarr != "") ''
      READARR_KEY=$(resolve_api_key '${arrKeys.readarr}' ${secretsDir}/readarr_api_key)
      printf 'READARR__AUTH__APIKEY=%s\n' "$READARR_KEY" > ${secretsDir}/readarr.env
      chmod 600 ${secretsDir}/readarr.env
    ''}
    ${lib.optionalString (arrKeys.jellyfin != "") ''
      JELLYFIN_KEY=$(resolve_api_key '${arrKeys.jellyfin}' ${secretsDir}/jellyfin_api_key)
      :
    ''}

    if [ -n "${arrKeys.jellyseerr}" ]; then
      SEERR_KEY='${arrKeys.jellyseerr}'
    elif [ -s ${secretsDir}/jellyseerr_api_key ]; then
      SEERR_KEY=$(cat ${secretsDir}/jellyseerr_api_key)
    else
      SEERR_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 16)
    fi
    printf '%s' "$SEERR_KEY" > ${secretsDir}/jellyseerr_api_key
    printf 'API_KEY=%s\n' "$SEERR_KEY" > ${secretsDir}/jellyseerr.env
    chmod 600 ${secretsDir}/jellyseerr_api_key ${secretsDir}/jellyseerr.env

    resolve_password '${arrKeys.jellyfinAdminPassword}' ${secretsDir}/jellyfin_admin_password 12

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
