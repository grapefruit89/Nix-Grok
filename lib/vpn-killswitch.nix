{ lib, privadoEnabled ? false }:

lib.mkIf privadoEnabled {
  bindsTo = [ "wireguard-privado.service" ];
  after = [ "wireguard-privado.service" ];
  requires = [ "network-online.target" ];
  
  # Strict network interface isolation for VPN
  serviceConfig = {
    RestrictNetworkInterfaces = [ "lo" "privado" ];
    IPAddressDeny = [ "any" ];
    IPAddressAllow = [ "localhost" "10.0.0.0/8" "192.168.0.0/16" "172.16.0.0/12" ];
  };
}
