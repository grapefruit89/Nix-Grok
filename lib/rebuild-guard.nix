# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Globale Rebuild-Sperre — Event-Path-Units pausieren während switch/test
#   tags:
#     - rebuild
#     - guard
# ---
{ lib }:
{
  sentinel = "/run/nixos/rebuild-in-progress";
  pathUnitGuard = {
    ConditionPathExists = "!/run/nixos/rebuild-in-progress";
  };
  stormPathUnits = [
    "security-watchdog-switch.path"
    "nixos-docs-indexer-switch.path"
    "nixos-docs-indexer-flake.path"
    "nixos-docs-embedder-db.path"
    "nftables-geoip-update-switch.path"
    "process-delete-queue.path"
    "process-delete-queue-tierc.path"
    "jellyfin-transcode-cleanup.path"
    "usenet-vpn-carrier.path"
    "usenet-vpn-operstate.path"
    "dns-guard-secrets.path"
    "dns-guard-ddns-config.path"
    "dns-guard-ddns-updates.path"
  ];
}
