# ---
# meta:
#   id: NIXH-90-POL-001
#   layer: 3
#   role: module
#   purpose: Globale [SEC-*]-Assertions bei aktivierter Firewall / Production
#   docs:
#     - docs/SPEC_REGISTRY.md
#   tags:
#     - security
#     - assertions
# ---
{ config, lib, ... }:

let
  must = assertion: message: { inherit assertion message; };
  sshSettings = config.services.openssh.settings or { };
  hardened = config.my.security.firewall.enable;
  production = config.my.mode == "production";
in
{
  config.assertions =
    (lib.optionals hardened [
      (must (config.my.security.firewall.enable == true) "[SEC-NET-001] Firewall aktiv (nftables-Modul).")
      (must (config.networking.nftables.enable == true) "[SEC-NET-002] NFTables aktiv.")
    ])
    ++ (lib.optionals production [
      (must (sshSettings.PermitRootLogin == "no") "[SEC-SSH-002] No Root SSH.")
      (must (!(sshSettings.PasswordAuthentication or false)) "[SEC-SSH-003] Kein Passwort-SSH.")
    ]);
}