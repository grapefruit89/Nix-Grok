# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: CIDR-Listen aus my.configs / my.security — keine hardcodierten Netze in Modulen
#   tags:
#     - network
#     - cidr
# ---
{ lib, config }:
let
  fw = config.my.security.firewall;
  net = config.my.configs.network;
  loopbackV4 = "127.0.0.0/8";
  loopbackV6 = "::1/128";
  trustedPrivateCidrs = fw.lanCidrs ++ [ net.netbirdCidr ];
in
{
  inherit loopbackV4 loopbackV6 trustedPrivateCidrs;

  lanCidrList = lib.concatStringsSep ", " fw.lanCidrs;

  trustedPrivateCidrList = lib.concatStringsSep ", " trustedPrivateCidrs;

  sshMatchAddresses = lib.concatStringsSep "," (
    [
      "127.0.0.1"
      loopbackV6
    ]
    ++ fw.lanCidrs
    ++ [ net.netbirdCidr ]
  );

  wanBogonCidrList = lib.concatStringsSep ", " net.wanBogonCidrs;
}
