# ---
# id: "network"
# domain: "10"
# status: "active"
# layer: 4
# purpose: "Domäne 10-network — aggregiert Kern-Netzwerk, VPN-Confinement, Gateway, Ingress"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["network", "imports"]
# ---
{ ... }:

{
  imports = [
    ./1010-network.nix
    ./1020-vpn-confinement.nix
    ./1030-gateway.nix
    ./1040-ingress.nix
  ];
}
