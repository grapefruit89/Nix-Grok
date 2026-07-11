# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Routing-Tabellen, Policy-Routing und Protokoll-Ports (keine Magic Numbers in Modulen)
#   docs:
#     - docs/adr/5031-usenet-vpn-sandbox.md
#   tags:
#     - routing
#     - vpn
#     - network
# ---
{ lib, ... }:
{
  options.my.network = {
    routing = {
      privadoTableId = lib.mkOption {
        type = lib.types.int;
        default = 51820;
        description = ''
          Routing table ID für Privado UID-Split-Tunnel (ip route/rule table).
          Unabhängig von my.ports.netbird-wg — zufällig gleiche Zahl, andere Semantik.
        '';
      };

      privadoTableName = lib.mkOption {
        type = lib.types.str;
        default = "privado";
        description = ''
          Name der Privado-Routing-Tabelle in systemd-networkd (RouteTable + [Route] Table=).
          Muss mit routeTables.<name> und netdev-Interface privado konsistent bleiben.
        '';
      };

      uidRulePriorityBase = lib.mkOption {
        type = lib.types.int;
        default = 90000;
        description = ''
          Basis für ip rule priority pro UID: priority = base + uid (5006 → 95006).
        '';
      };
    };

    protocol = {
      dns = lib.mkOption {
        type = lib.types.port;
        default = 53;
        description = "IANA DNS — Blocky LAN-Listener, Firewall-Exceptions.";
      };
      dot = lib.mkOption {
        type = lib.types.port;
        default = 853;
        description = "DNS-over-TLS — resolved/Blocky Upstream-Port.";
      };
    };
  };
}
