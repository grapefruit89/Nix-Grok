# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Media-Domain — Submodule-Aggregation und Enable-Optionen
#   tags:
#     - media
#     - imports
# ---
{ lib, ... }:

{
  imports = [
    ./jellyfin.nix
    ./audiobookshelf.nix
    ./arr.nix
    ./sabnzbd.nix
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
    audiobookshelf = {
      enable = lib.mkEnableOption "Audiobookshelf — H\u00f6rb\u00fccher & Podcasts";
      enableQuickSync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Intel VA-API f\u00fcr ffmpeg-Transcode (iGPU UHD 630).";
      };
    };
  };
}
