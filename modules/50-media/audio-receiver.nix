{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.audio-receiver;
in
{
  options.my.services.audio-receiver = {
    enable = lib.mkEnableOption "Open Source Audio Receivers (AirPlay & DLNA)";
    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "NixOS-Speaker";
      description = "Name broadcasted to the network";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. AirPlay Receiver (shairport-sync)
    services.shairport-sync = {
      enable = true;
      arguments = "-a '${cfg.deviceName}'";
      openFirewall = true;
    };

    # 2. UPnP / DLNA Receiver (upmpdcli + mpd)
    services.mpd = {
      enable = true;
      extraConfig = ''
        audio_output {
          type "pulse"
          name "PulseAudio"
        }
      '';
      network.listenAddress = "any";
    };

    services.upmpdcli = {
      enable = true;
      configuration = {
        friendlyname = "${cfg.deviceName} (DLNA)";
      };
    };

    # Open ports for UPnP/DLNA
    networking.firewall.allowedTCPPorts = [ 49152 6600 ];
    networking.firewall.allowedUDPPorts = [ 1900 ];
  };
}
