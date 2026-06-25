{ config, pkgs, lib, ... }:

{
  options.services.aider = {
    enable = lib.mkEnableOption "Aider AI coding assistant";
  };

  config = lib.mkIf config.services.aider.enable {
    environment.systemPackages = with pkgs; [
      aider-chat
      uv
    ];

    programs.nix-ld.enable = true;
  };
}
