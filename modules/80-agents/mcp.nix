# ---
# meta:
#   layer: 3
#   role: module
#   purpose: MCP-Indexer + Import zentraler mcp/-Schicht
#   tags:
#     - mcp
# ---
{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../../mcp ];

  config = {
    my.mcp.enable = lib.mkDefault true;
    my.mcp.enableExa = lib.mkDefault true;

    systemd.services.nixos-docs-indexer = {
      description = "Indexiert /etc/nixos in nixos_docs.sqlite (FTS + Meta + Chunks)";
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 /etc/nixos/scripts/index-nix-files.py";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadOnlyPaths = [ "/etc/nixos" ];
        ReadWritePaths = [ "/var/lib/nixos-docs-mcp" ];
      };
    };

    systemd.timers.nixos-docs-indexer = {
      description = "nixos-docs Indexer Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        Persistent = true;
      };
    };
  };
}
