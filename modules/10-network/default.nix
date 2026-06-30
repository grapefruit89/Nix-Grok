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
    ./11-network.nix
    ./12-vpn-confinement.nix
    ./13-gateway.nix
    ./14-ingress.nix
    ./15-databases.nix
    ./16-vpn.nix
    ./17-pocket-id.nix
  ];
}
