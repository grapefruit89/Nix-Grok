# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Upstream-Host für Services in VPN-NetNS (nixflix/nixarr connectionAddress)
#   tags:
#     - vpn
#     - netns
# ---
{lib}: let
  servicePorts = {
    sabnzbd = "sabnzbd";
    prowlarr = "prowlarr";
  };
in rec {
  findNamespace = cfg: serviceName:
    lib.findFirst (nsName: lib.elem serviceName (cfg.namespaces.${nsName}.services or [])) null (
      lib.attrNames cfg.namespaces
    );

  namespaceFor = cfg: serviceName: let
    nsName = findNamespace cfg serviceName;
  in
    if nsName == null
    then null
    else cfg.namespaces.${nsName};

  connectionAddress = cfg: serviceName:
    if !(cfg.enable or false)
    then "127.0.0.1"
    else let
      ns = namespaceFor cfg serviceName;
    in
      if ns == null
      then "127.0.0.1"
      else ns.namespaceAddress;

  hostBridgeAddress = cfg: serviceName:
    if !(cfg.enable or false)
    then "127.0.0.1"
    else let
      ns = namespaceFor cfg serviceName;
    in
      if ns == null
      then "127.0.0.1"
      else ns.bridgeAddress;

  isVpnConfined = cfg: serviceName: cfg.enable or false && namespaceFor cfg serviceName != null;

  servicePort = ports: serviceName: ports.${servicePorts.${serviceName} or serviceName} or null;
}
