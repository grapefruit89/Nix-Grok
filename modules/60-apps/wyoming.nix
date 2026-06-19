{ config, lib, ... }:

let
  cfgWyoming = config.my.services.wyoming-stt;
in
{
  options.my.services.wyoming-stt.enable = lib.mkEnableOption "Wyoming Protocol STT (Parakeet TDT)";

  config = lib.mkIf cfgWyoming.enable {
    virtualisation.oci-containers.containers.wyoming-stt-nemo = {
      image = "ghcr.io/tboby/wyoming-onnx-asr:latest";
      ports = [ "10300:10300" ];
      volumes = [ "/data/state/wyoming:/data" ];
      cmd = [
        "--uri" "tcp://0.0.0.0:10300"
        "--model-multilingual" "nemo-parakeet-tdt-0.6b-v3"
        "--model-dir" "/data"
        "--device" "cpu" 
      ];
      autoStart = true;
    };

    # Open the Wyoming protocol port for Home Assistant
    networking.firewall.allowedTCPPorts = [ 10300 ];

    # Ensure the local state directory exists for the model cache
    systemd.tmpfiles.rules = [
      "d /data/state/wyoming 0750 root root -"
    ];
  };
}
