# q958 — Datei-Secrets unter /var/lib/secrets (vorläufig statt SOPS).
{ config, lib, pkgs, ... }:

let
  p = import ./profile.nix;
  secretsDir = p.secrets.dir;
  dk = p.secrets.devKeys;
  moritz = (import ../../users/moritz/profile.nix).name;

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

    echo "${dk.restic.password}" > ${secretsDir}/restic_password
    chmod 600 ${secretsDir}/restic_password

    echo "${dk.media.prowlarr.apiKey}" > ${secretsDir}/prowlarr_api_key
    echo "${dk.media.sonarr.apiKey}" > ${secretsDir}/sonarr_api_key
    echo "${dk.media.radarr.apiKey}" > ${secretsDir}/radarr_api_key
    echo "${dk.media.sabnzbd.apiKey}" > ${secretsDir}/sabnzbd_api_key
    echo "${dk.media.scenenzbs.apiKey}" > ${secretsDir}/scenenzbs_api_key
    chmod 600 ${secretsDir}/prowlarr_api_key ${secretsDir}/sonarr_api_key \
      ${secretsDir}/radarr_api_key ${secretsDir}/sabnzbd_api_key ${secretsDir}/scenenzbs_api_key

    echo "ADMIN_TOKEN=${dk.vaultwarden.adminToken}" > ${secretsDir}/vaultwarden.env
    chmod 600 ${secretsDir}/vaultwarden.env

    # Context7: nur wenn in profile.nix gesetzt; sonst Datei mit Hinweis
    if [ -n "${dk.context7.apiKey}" ]; then
      echo "CONTEXT7_API_KEY=${dk.context7.apiKey}" > ${secretsDir}/${p.secrets.files.context7}
      chmod 600 ${secretsDir}/${p.secrets.files.context7}
      install -d -m 700 -o ${moritz} -g users /home/${moritz}/.config/context7
      printf '%s' "${dk.context7.apiKey}" > /home/${moritz}/.config/context7/api_key
      chown ${moritz}:users /home/${moritz}/.config/context7/api_key
      chmod 600 /home/${moritz}/.config/context7/api_key
    elif [ ! -f ${secretsDir}/${p.secrets.files.context7} ]; then
      cat > ${secretsDir}/${p.secrets.files.context7} <<'CTX7EOF'
# Context7 API-Key — einer der Wege:
#   1) Als moritz: set-context7-api-key   (empfohlen, Key nicht im Terminal-Log)
#   2) In profile.nix: secrets.devKeys.context7.apiKey = "…"; dann rebuild
CTX7EOF
      chmod 600 ${secretsDir}/${p.secrets.files.context7}
    fi

    # Grok: System-Secret → User-Home wenn Key in context7.env steht
    if [ -f ${secretsDir}/${p.secrets.files.context7} ] && \
       grep -q '^CONTEXT7_API_KEY=.\+' ${secretsDir}/${p.secrets.files.context7} 2>/dev/null; then
      _ctx7=$(grep '^CONTEXT7_API_KEY=' ${secretsDir}/${p.secrets.files.context7} | cut -d= -f2-)
      install -d -m 700 -o ${moritz} -g users /home/${moritz}/.config/context7
      printf '%s' "$_ctx7" > /home/${moritz}/.config/context7/api_key
      chown ${moritz}:users /home/${moritz}/.config/context7/api_key
      chmod 600 /home/${moritz}/.config/context7/api_key
      unset _ctx7
    fi
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${secretsDir} 0700 root root -"
    "d /etc/gatus 0755 root root -"
  ];

  environment.etc."gatus/endpoints.yaml".source = ./gatus-endpoints.yaml;

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
      "home-manager-${moritz}.service"
    ];
  };
}