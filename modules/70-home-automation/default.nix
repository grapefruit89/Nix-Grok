# ---
# meta:
#   layer: 3
#   role: domain
#   purpose: Home Automation — Home Assistant, Mosquitto, Zigbee2MQTT
#   tags:
#     - iot
#     - home-automation
# ---
{ ... }:
{
  imports = [
    ./home-assistant.nix
    ./zigbee-stack.nix
  ];
}
