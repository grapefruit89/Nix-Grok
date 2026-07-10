# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Secret-Provisionierung unter /var/lib/secrets (vor SOPS)
#   tags:
#     - secrets
#     - provision
# ---
{
  lib,
  pkgs,
  ...
}:
let
  p = import ./profile.nix;
  # Absolutpfad-Fallback wie profile.nix — nötig wenn ./profile.local.nix beim Flake-Build
  # nicht im Store liegt (gitignored). Mit --impure ist der Absolutpfad immer erreichbar.
  localPath =
    if builtins.pathExists ./profile.local.nix then
      ./profile.local.nix
    else if builtins.pathExists /etc/nixos/machines/q958/profile.local.nix then
      /etc/nixos/machines/q958/profile.local.nix
    else
      null;
  local = if localPath != null then import localPath else { };
  secretsDir = p.secrets.dir;
  dk = p.secrets.devKeys;
  privadoKey = local.secrets.privado.privateKey or "";
  resticS3 = local.secrets.restic or { };
  ampPassword =
    (dk.amp or { }).adminPassword
      or (throw "secrets.devKeys.amp.adminPassword in profile.local.nix setzen");
  ampUser = (dk.amp or { }).adminUser or "admin";
  resticRepository = resticS3.repository or "";
  resticAwsKey = resticS3.awsAccessKeyId or "";
  resticAwsSecret = resticS3.awsSecretAccessKey or "";
  resticMega = local.secrets.resticMega or { };
  resticMegaEnable = resticMega.enable or false;
  resticMegaUser = resticMega.user or "";
  resticMegaPass = resticMega.obscuredPass or "";
  hassMqttPassword =
    (dk.homeassistant or { }).mqttPassword
      or (throw "secrets.devKeys.homeassistant.mqttPassword in profile.local.nix setzen");
  zigbeeMqttPassword =
    (dk.zigbee or { }).mqttPassword
      or (throw "secrets.devKeys.zigbee.mqttPassword in profile.local.nix setzen");
  adminUser = (import ../../users/admin/profile.nix).name;
  cfToken = (local.secrets.cloudflare or { }).apiToken or "";
  ddnsZone = p.network.ddns.zone;
  oidcJellyfin = local.secrets.oidc.jellyfin or { };
  oidcNavidrome = local.secrets.oidc.navidrome or { };
  ddnsFqdn = p.network.ddns.fqdn;
  ddnsWildcardFqdn = p.network.ddns.wildcardFqdn;
  externalSubdomains = [
    "auth"
    "seerr"
    "files"
    "links"
    "ai"
    "paperless"
    "home"
    "zigbee"
    "amp"
  ];
  externalJqEntries = lib.concatStringsSep ",\n          " (
    map (
      sub:
      ''{provider: "cloudflare", zone_identifier: $zone_id, domain: "${sub}.${ddnsFqdn}", proxied: true, ttl: 1, token: $token, ip_version: "ipv4"}''
    ) externalSubdomains
  );
  oauth2ClientId = (local.secrets.devKeys.oauth2proxy or { }).clientId or "";
  oauth2ClientSecret = (local.secrets.devKeys.oauth2proxy or { }).clientSecret or "";
  googleTtsApiKey = (local.secrets.devKeys.googleTts or { }).apiKey or "";
  googleTtsVoice = (local.secrets.devKeys.googleTts or { }).voice or "";

  provisionScript = pkgs.writeShellScript "q958-secrets-provision" ''
        set -euo pipefail
        mkdir -p ${secretsDir}
        chmod 700 ${secretsDir}

        # Gatus: einmalig generiertes Keypair (kein Dev-String — SSH braucht Paar)
        if [ ! -f ${secretsDir}/gatus_ssh_key ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f ${secretsDir}/gatus_ssh_key -N "" -q
          chmod 600 ${secretsDir}/gatus_ssh_key
          chmod 600 ${secretsDir}/gatus_ssh_key.pub
        fi

        install -d -m 700 -o monitoring -g media /var/lib/monitoring/.ssh
        install -m 600 -o monitoring -g media ${secretsDir}/gatus_ssh_key.pub /var/lib/monitoring/.ssh/authorized_keys

        # Dev-Keys aus profile.nix — idempotent, kein openssl rand
        echo "ENCRYPTION_KEY=${dk.pocketId.encryptionKey}" > ${secretsDir}/${p.secrets.files.pocketId}
        chmod 600 ${secretsDir}/${p.secrets.files.pocketId}

        echo "${dk.grafana.secretKey}" > ${secretsDir}/grafana_secret_key
        chmod 600 ${secretsDir}/grafana_secret_key

        # OIDC-Secrets: Jellyfin + Navidrome — nur provisionieren wenn in profile.local.nix gesetzt
        # Pocket-ID → Applications → New → Callback-URL prüfen, dann clientId+clientSecret hier setzen:
        #   secrets.oidc.jellyfin  = { clientId = "..."; clientSecret = "..."; };
        #   secrets.oidc.navidrome = { clientId = "..."; clientSecret = "..."; };
        _jf_id="${oidcJellyfin.clientId or ""}"
        _jf_secret="${oidcJellyfin.clientSecret or ""}"
        if [ -n "$_jf_id" ] && [ -n "$_jf_secret" ]; then
          { echo "ND_OIDCCLIENTID=$_jf_id"; echo "ND_OIDCCLIENTSECRET=$_jf_secret"; } \
            > ${secretsDir}/${p.secrets.files.jellyfinOidc}
          chmod 600 ${secretsDir}/${p.secrets.files.jellyfinOidc}
        fi
        unset _jf_id _jf_secret
        _nd_id="${oidcNavidrome.clientId or ""}"
        _nd_secret="${oidcNavidrome.clientSecret or ""}"
        if [ -n "$_nd_id" ] && [ -n "$_nd_secret" ]; then
          {
            echo "ND_OIDCENABLED=true"
            echo "ND_OIDCCLIENTID=$_nd_id"
            echo "ND_OIDCCLIENTSECRET=$_nd_secret"
          } > ${secretsDir}/${p.secrets.files.navdromeOidc}
          chmod 600 ${secretsDir}/${p.secrets.files.navdromeOidc}
        fi
        unset _nd_id _nd_secret

        echo "${dk.restic.password}" > ${secretsDir}/restic_password
        chmod 600 ${secretsDir}/restic_password

        # Media-API-Keys: siehe machines/q958/media-secrets.nix

        echo "ADMIN_TOKEN=${dk.vaultwarden.adminToken}" > ${secretsDir}/vaultwarden.env
        chmod 600 ${secretsDir}/vaultwarden.env

        cat > ${secretsDir}/amp.env <<AMPEOF
    AMP_ADMIN_USER=${ampUser}
    AMP_ADMIN_PASSWORD=${ampPassword}
    AMPEOF
        chmod 600 ${secretsDir}/amp.env

        # Mosquitto — nur Hash speichern (NixOS-Modul setzt "username:" selbst davor)
        rm -f ${secretsDir}/mosquitto_password ${secretsDir}/mosquitto_hass_password
        ${pkgs.mosquitto}/bin/mosquitto_passwd -b -c ${secretsDir}/mosquitto_password zigbee2mqtt "${zigbeeMqttPassword}"
        cut -d: -f2- ${secretsDir}/mosquitto_password > ${secretsDir}/.mosquitto_password_hash
        mv ${secretsDir}/.mosquitto_password_hash ${secretsDir}/mosquitto_password
        chmod 600 ${secretsDir}/mosquitto_password
        ${pkgs.mosquitto}/bin/mosquitto_passwd -b -c ${secretsDir}/mosquitto_hass_password homeassistant "${hassMqttPassword}"
        cut -d: -f2- ${secretsDir}/mosquitto_hass_password > ${secretsDir}/.mosquitto_hass_password_hash
        mv ${secretsDir}/.mosquitto_hass_password_hash ${secretsDir}/mosquitto_hass_password
        chmod 600 ${secretsDir}/mosquitto_hass_password
        printf '%s' "${hassMqttPassword}" > ${secretsDir}/homeassistant_mqtt_password
        chmod 600 ${secretsDir}/homeassistant_mqtt_password

        cat > ${secretsDir}/zigbee2mqtt.env <<Z2MEOF
    ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=${zigbeeMqttPassword}
    Z2MEOF
        chmod 600 ${secretsDir}/zigbee2mqtt.env

        # Restic S3 (Koofr) — Primär-Backup; leer = kein Offsite-Backup bis konfiguriert
        # secrets.restic in profile.local.nix: repository = "s3:s3.koofr.net/<bucket>/restic"
        if [ -n "${resticRepository}" ]; then
          cat > ${secretsDir}/restic_s3_creds <<RESTICEOF
    RESTIC_REPOSITORY=${resticRepository}
    AWS_ACCESS_KEY_ID=${resticAwsKey}
    AWS_SECRET_ACCESS_KEY=${resticAwsSecret}
    RESTICEOF
          chmod 600 ${secretsDir}/restic_s3_creds
        fi

        # Restic MEGA — Sekundär-Backup via rclone (Vaultwarden + Secrets)
        # secrets.resticMega in profile.local.nix: enable=true, user=email, obscuredPass=rclone-obscure-output
        if ${if resticMegaEnable then "true" else "false"}; then
          cat > ${secretsDir}/restic_mega_creds <<MEGAEOF
    RCLONE_CONFIG_MEGA_TYPE=mega
    RCLONE_CONFIG_MEGA_USER=${resticMegaUser}
    RCLONE_CONFIG_MEGA_PASS=${resticMegaPass}
    MEGAEOF
          chmod 600 ${secretsDir}/restic_mega_creds
        fi

        # Context7: nur wenn in profile.nix gesetzt; sonst Datei mit Hinweis
        if [ -n "${dk.context7.apiKey}" ]; then
          echo "CONTEXT7_API_KEY=${dk.context7.apiKey}" > ${secretsDir}/${p.secrets.files.context7}
          chmod 600 ${secretsDir}/${p.secrets.files.context7}
          install -d -m 700 -o ${adminUser} -g users /home/${adminUser}/.config/context7
          printf '%s' "${dk.context7.apiKey}" > /home/${adminUser}/.config/context7/api_key
          chown ${adminUser}:users /home/${adminUser}/.config/context7/api_key
          chmod 600 /home/${adminUser}/.config/context7/api_key
        elif [ ! -f ${secretsDir}/${p.secrets.files.context7} ]; then
          cat > ${secretsDir}/${p.secrets.files.context7} <<'CTX7EOF'
    # Context7 API-Key — einer der Wege:
    #   1) Als admin: set-context7-api-key   (empfohlen, Key nicht im Terminal-Log)
    #   2) In profile.nix: secrets.devKeys.context7.apiKey = "…"; dann rebuild
    CTX7EOF
          chmod 600 ${secretsDir}/${p.secrets.files.context7}
        fi

        # Cloudflare DDNS — Token + qdm12/ddns-updater config.json (Zone-ID per API)
        # + ACME environmentFile (CF_DNS_API_TOKEN=... für lego/security.acme)
        if [ -n "${cfToken}" ]; then
          printf '%s' "${cfToken}" > ${secretsDir}/cloudflare_api_token
          chmod 600 ${secretsDir}/cloudflare_api_token
          printf 'CF_DNS_API_TOKEN=%s\n' "${cfToken}" > ${secretsDir}/cloudflare_acme_env
          chmod 600 ${secretsDir}/cloudflare_acme_env
          ZONE_DATA=$(${pkgs.curl}/bin/curl -sf -X GET \
            "https://api.cloudflare.com/client/v4/zones?name=${ddnsZone}" \
            -H "Authorization: Bearer ${cfToken}" -H "Content-Type: application/json")
          ZONE_ID=$(${pkgs.jq}/bin/jq -r '.result[0].id // empty' <<< "$ZONE_DATA")
          if [ -z "$ZONE_ID" ]; then
            echo "DDNS: Cloudflare Zone ${ddnsZone} nicht gefunden — Token prüfen"
            exit 1
          fi
          ${pkgs.jq}/bin/jq -n \
            --arg token "${cfToken}" \
            --arg zone_id "$ZONE_ID" \
            --arg domain "${ddnsFqdn}" \
            --arg wildcard "${ddnsWildcardFqdn}" \
            '{
              settings: [
                {provider: "cloudflare", zone_identifier: $zone_id, domain: $domain,   proxied: false, ttl: 1, token: $token, ip_version: "ipv4"},
                {provider: "cloudflare", zone_identifier: $zone_id, domain: $wildcard, proxied: false, ttl: 1, token: $token, ip_version: "ipv4"},
                ${externalJqEntries}
              ]
            }' > ${secretsDir}/ddns-updater-config.json
          chmod 600 ${secretsDir}/ddns-updater-config.json
          install -d -m 755 -o ddns-updater -g ddns-updater /var/lib/ddns-updater
          install -m 600 -o ddns-updater -g ddns-updater \
            ${secretsDir}/ddns-updater-config.json /var/lib/ddns-updater/config.json
        fi

        # Privado WG — Key aus profile.local.nix → .env + Keyfile für wg-quick
        if [ -n "${privadoKey}" ]; then
          printf '%s' "${privadoKey}" > ${secretsDir}/${p.secrets.files.privadoKey}
          chmod 600 ${secretsDir}/${p.secrets.files.privadoKey}
          cat > ${secretsDir}/${p.secrets.files.privadoEnv} <<PRIVADOEOF
    PRIVADO_PRIVATE_KEY=${privadoKey}
    PRIVADO_ADDRESS=${p.network.privado.address}
    PRIVADO_ENDPOINT=${p.network.privado.endpoint}
    PRIVADO_PUBLIC_KEY=${p.network.privado.publicKey}
    PRIVADO_DNS=${lib.concatStringsSep "," p.network.privado.dns}
    PRIVADOEOF
          chmod 600 ${secretsDir}/${p.secrets.files.privadoEnv}
          cat > ${secretsDir}/privado.netns.conf <<NETNSEOF
    [Interface]
    PrivateKey = ${privadoKey}
    [Peer]
    PublicKey = ${p.network.privado.publicKey}
    Endpoint = ${p.network.privado.endpoint}
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    NETNSEOF
          chmod 600 ${secretsDir}/privado.netns.conf
        fi

        # oauth2-proxy OIDC-Client (Pocket-ID App-Registrierung)
        # In profile.local.nix setzen: secrets.devKeys.oauth2proxy = { clientId = "..."; clientSecret = "..."; }
        if [ -n "${oauth2ClientId}" ] && [ -n "${oauth2ClientSecret}" ]; then
          printf 'OAUTH2_PROXY_CLIENT_ID=%s\nOAUTH2_PROXY_CLIENT_SECRET=%s\n' \
            "${oauth2ClientId}" "${oauth2ClientSecret}" > ${secretsDir}/oauth2-proxy.env
        elif [ ! -f ${secretsDir}/oauth2-proxy.env ]; then
          # Placeholder damit oauth2-proxy starten kann — wird durch echte Credentials ersetzt
          printf 'OAUTH2_PROXY_CLIENT_ID=setup-pending\nOAUTH2_PROXY_CLIENT_SECRET=setup-pending\n' \
            > ${secretsDir}/oauth2-proxy.env
        fi
        chmod 600 ${secretsDir}/oauth2-proxy.env
        # Cookie-Secret — einmalig generiert, nie überschrieben.
        # Muss exakt 32 Bytes sein (AES-256). openssl rand -base64 24 → 32 Chars, kein Newline.
        if [ ! -f ${secretsDir}/oauth2-proxy-cookie-secret ] || \
           [ "$(wc -c < ${secretsDir}/oauth2-proxy-cookie-secret)" != "32" ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '\n' > ${secretsDir}/oauth2-proxy-cookie-secret
          chmod 600 ${secretsDir}/oauth2-proxy-cookie-secret
        fi

        # Google Cloud TTS — API Key versiegeln + Voice-Name in env-Datei
        # Eintragen in profile.local.nix: secrets.devKeys.googleTts = { apiKey = "AIza..."; voice = "de-DE-Chirp3-HD-Aoede"; };
        if [ -n "${googleTtsApiKey}" ]; then
          printf '%s' "${googleTtsApiKey}" | \
            ${pkgs.systemd}/lib/systemd/systemd-creds encrypt --name=google_tts_api_key - \
              /var/lib/credstore.encrypted/google_tts_api_key.cred
          printf 'GOOGLE_TTS_VOICE=%s\n' "${googleTtsVoice}" > ${secretsDir}/google-tts.env
          chmod 600 ${secretsDir}/google-tts.env
        fi

        # Grok: System-Secret → User-Home wenn Key in context7.env steht
        if [ -f ${secretsDir}/${p.secrets.files.context7} ] && \
           grep -q '^CONTEXT7_API_KEY=.\+' ${secretsDir}/${p.secrets.files.context7} 2>/dev/null; then
          _ctx7=$(grep '^CONTEXT7_API_KEY=' ${secretsDir}/${p.secrets.files.context7} | cut -d= -f2-)
          install -d -m 700 -o ${adminUser} -g users /home/${adminUser}/.config/context7
          printf '%s' "$_ctx7" > /home/${adminUser}/.config/context7/api_key
          chown ${adminUser}:users /home/${adminUser}/.config/context7/api_key
          chmod 600 /home/${adminUser}/.config/context7/api_key
          unset _ctx7
        fi
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${secretsDir} 0700 root root -"
  ];

  system.activationScripts.q958SecretsProvision.text = builtins.readFile provisionScript;

  systemd.services.q958-secrets-provision = {
    description = "Provision /var/lib/secrets Dev-Keys (q958 profile.nix)";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = provisionScript;
    };
    wantedBy = [ "multi-user.target" ];
    before = [
      "sshd.service"
      "gatus.service"
      "grafana.service"
      "pocket-id.service"
      "home-manager-${adminUser}.service"
      "mosquitto.service"
      "home-assistant-mqtt-provision.service"
      "home-assistant.service"
      "ddns-updater.service"
      "oauth2-proxy.service"
      "google-tts-wyoming.service"
    ];
  };
}
