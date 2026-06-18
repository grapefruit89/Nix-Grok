{ config, lib, ... }:

let
  cfg = config.my.hardware.slzb-06m;
in
{
  options.my.hardware.slzb-06m = {
    enable = lib.mkEnableOption "SLZB-06M LAN Zigbee Coordinator";
    host = lib.mkOption {
      type = lib.types.str;
      default = "SLZB-06M.local"; # mDNS Auto-Discovery
      description = "Hostname (mDNS) oder IP des Sticks";
    };
    transmitPower = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Sendeleistung (max 20 für CC2652P/EFR32)";
    };
    disableLed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Grüne Status-LED am Stick deaktivieren";
    };
  };

  config = lib.mkIf cfg.enable {
    # Überschreibe den Zigbee-Stack mit unseren Hardware-Werten
    my.services.zigbee-stack = {
      adapter = "ember";
      zigbeeDevice = "tcp://${cfg.host}:6638";
    };

    # Injiziere die spezifischen Hardware-Settings direkt in Z2M
    services.zigbee2mqtt.settings = {
      serial = {
        baudrate = 115200;
        disable_led = cfg.disableLed;
      };
      advanced = {
        transmit_power = cfg.transmitPower;
      };
    };
  };
}
