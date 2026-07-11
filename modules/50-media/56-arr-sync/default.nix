{ ... }:
{
  imports = [
    ./locale.nix
    ./prowlarr.nix
    ./download-clients.nix
    ./seerr.nix
    ./settings.nix
    ./keys.nix
    ./profiles.nix
    ./jellyfin-sync.nix
  ];

  options.my.media.sync = { };
}
