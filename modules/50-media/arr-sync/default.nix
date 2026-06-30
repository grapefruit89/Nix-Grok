{
  config,
  lib,
  ...
}:
let
  anyEnabled =
    config.my.services.sonarr.enable
    || config.my.services.radarr.enable
    || config.my.services.prowlarr.enable
    || config.my.services.sabnzbd.enable
    || config.my.services.jellyfin.enable;
in
{
  imports = [
    ./locale.nix
    ./prowlarr.nix
    ./download-clients.nix
  ];

  options.my.media.sync = {
    # Lokaler Helper: fokussierten oneshot-Sync-Service erstellen.
    # Wird von den Submodulen (prowlarr.nix etc.) genutzt.
  };

  # Globale Enable-Bedingung: Sync-Services nur wenn mindestens ein Media-Service aktiv
  config = lib.mkIf anyEnabled {
    # Gemeinsame Pakete, die alle Sync-Services brauchen
    # (werden per `path` in den Einzelservices gesetzt — kein globales Paket nötig)
  };
}
