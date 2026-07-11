# ---
# id: "network"
# domain: "10"
# status: "active"
# layer: 4
# purpose: "Domäne 10-network — aggregiert Kern-Netzwerk, Gateway, Ingress"
# schema: "100x=Service-Port, 109x=Infrastruktur (ADR-011 Isomorphie)"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["network", "imports"]
# ---
{ ... }:
{
  imports = [
    ./1090-host-network.nix
    ./1002-blocky.nix
    ./1003-gateway.nix
    ./1094-ingress.nix
    ./1095-databases.nix
    ./1096-vpn.nix
    ./1001-pocket-id.nix
  ];
}
