{ config, lib, pkgs, ... }:

let 
  cfg = config.my.services.voice-assistant;
in 
{
  options.my.services.voice-assistant = {
    enable = lib.mkEnableOption "Wyoming Voice Assistant Pipeline";
  };

  config = lib.mkIf cfg.enable {
    # 1. Native Wake Word Erkennung
    services.wyoming.openwakeword = {
      enable = true;
      preloadModels = [ "ok_nabu" ];
    };

    # 2. Native Text-to-Speech (Antworten generieren)
    services.wyoming.piper = {
      enable = true;
      servers."de-de".voice = "de_DE-thorsten-medium";
    };

    # 3. Speech-to-Text (Parakeet via Podman)
    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers."wyoming-parakeet" = {
      image = "ghcr.io/tboby/wyoming-onnx-asr:latest";
      ports = [ "127.0.0.1:10300:10300" ];
      volumes = [ "/var/cache/wyoming-parakeet:/data" ]; # Caching in Tier B
      cmd = [
        "--uri" "tcp://0.0.0.0:10300"
        "--model-multilingual" "nemo-parakeet-tdt-0.6b-v3"
        "--model-dir" "/data"
        "--device" "cpu" 
      ];
    };

    # Firewall Ports lokal öffnen (piper=10200, openwakeword=10400, parakeet=10300)
    networking.firewall.allowedTCPPorts = [ 10200 10300 10400 ];

    # Ensure cache directory exists
    systemd.tmpfiles.rules = [
      "d /var/cache/wyoming-parakeet 0750 root root -"
    ];
  };
}
