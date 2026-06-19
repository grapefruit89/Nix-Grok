{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Desktop is normally in development mode
  my.mode = lib.mkDefault "development";

  # Enable desktop features (X11, audio, etc.)
  services.xserver.enable = lib.mkDefault true;
  services.pulseaudio.enable = lib.mkDefault true;
  networking.networkmanager.enable = lib.mkDefault true;
}
