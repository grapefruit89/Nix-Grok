# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: VPN-Kill-Switch systemd-Attrs für privado WireGuard
#   tags:
#     - vpn
#     - privado
# ---
{ lib, privadoEnabled }:

lib.optionalAttrs privadoEnabled {
  bindsTo = [ "sys-subsystem-net-devices-privado.device" ];
  after = [ "sys-subsystem-net-devices-privado.device" ];
  serviceConfig.RestrictNetworkInterfaces = [
    "lo"
    "privado"
  ];
}
