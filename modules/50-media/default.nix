
{ lib, ... }:

{
  imports = [
    ./jellyfin.nix
    ./arr-stack.nix
    ./sabnzbd.nix
    ./audiobookshelf.nix
    ./sync.nix
  ];

  # Centralized options declaration for domain 50
  options.my.services = {
    jellyfin.enable = lib.mkEnableOption "Jellyfin Media Server with Intel QuickSync";
    jellyseerr.enable = lib.mkEnableOption "Jellyseerr Request Manager";
    sonarr.enable = lib.mkEnableOption "Sonarr Series Manager";
    radarr.enable = lib.mkEnableOption "Radarr Movies Manager";
    readarr.enable = lib.mkEnableOption "Readarr Books Manager";
    prowlarr.enable = lib.mkEnableOption "Prowlarr Indexer Proxy";
    sabnzbd.enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
    audiobookshelf.enable = lib.mkEnableOption "Audiobookshelf Server";
  };
}
