# Helfer: Dev-Mode-Warnung für Platzhalter-Secrets (bricht den Build nicht).
{ lib, secretsDir, devKeys, files }:

let
  # Nur Keys mit festem Dev-Wert in profile.nix — kein Zufall, kein openssl rand
  provisioned = [
    {
      label = "Pocket-ID ENCRYPTION_KEY";
      path = "${secretsDir}/${files.pocketId}";
      value = devKeys.pocketId.encryptionKey;
    }
    {
      label = "Grafana secret_key";
      path = "${secretsDir}/grafana_secret_key";
      value = devKeys.grafana.secretKey;
    }
    {
      label = "Context7 API (Grok/Hermes)";
      path = "${secretsDir}/${files.context7}";
      value = devKeys.context7.apiKey;
      optional = true;
    }
    {
      label = "Restic backup password";
      path = "${secretsDir}/restic_password";
      value = devKeys.restic.password;
    }
    {
      label = "Prowlarr API key";
      path = "${secretsDir}/prowlarr_api_key";
      value = devKeys.media.prowlarr.apiKey;
    }
    {
      label = "Sonarr API key";
      path = "${secretsDir}/sonarr_api_key";
      value = devKeys.media.sonarr.apiKey;
    }
    {
      label = "Radarr API key";
      path = "${secretsDir}/radarr_api_key";
      value = devKeys.media.radarr.apiKey;
    }
    {
      label = "SABnzbd API key";
      path = "${secretsDir}/sabnzbd_api_key";
      value = devKeys.media.sabnzbd.apiKey;
    }
    {
      label = "SceneNZBs API key";
      path = "${secretsDir}/scenenzbs_api_key";
      value = devKeys.media.scenenzbs.apiKey;
    }
    {
      label = "Vaultwarden admin token";
      path = "${secretsDir}/vaultwarden.env";
      value = "ADMIN_TOKEN=${devKeys.vaultwarden.adminToken}";
    }
  ];

  isUnset = value: value == "" || lib.hasPrefix "CHANGE-ME" value;

  warningBullet = e:
    let
      status =
        if isUnset e.value
        then "MANUELL SETZEN"
        else "DEV-PLATZHALTER — vor Production ersetzen";
    in "  • ${e.label}: ${e.path} (${status})";

  mkWarning = { rolloutStufe, mode }:
    lib.optionalString (mode == "development") ''
      ══ q958 DEVELOPMENT MODE (rollout.stufe = ${toString rolloutStufe}) ══
      Platzhalter-Secrets aktiv — vor SOPS/Production durch echte Werte ersetzen:

      ${lib.concatStringsSep "\n" (map warningBullet provisioned)}

        • Gatus SSH-Keypair: ${secretsDir}/gatus_ssh_key (einmalig generiert, OK für Dev)
        • Grok Context7 (interaktiv): set-context7-api-key → ~/.config/context7/api_key
        • Grok MCP: context7 (Key) + mcp-nixos + nixos_docs (sync-nixos-docs-db) — check-grok-mcp

      Dev-Keys zentral: machines/q958/profile.nix → secrets.devKeys
      ══════════════════════════════════════════════════════════════════════
    '';
in
{
  inherit provisioned isUnset mkWarning warningBullet;
}