# ---
# meta:
#   layer: 5
#   role: aggregator
#   purpose: Zentrale, modellunabhaengige MCP-Server-Definitionen
#   docs:
#     - mcp/README.md
#   tags:
#     - mcp
# ---
{
  pkgs,
  mcpConfigFile,
  ...
}:
{
  # Schreibt die ueber natsukium/mcp-servers-nix generierte Konfiguration
  # nach /etc/nixos/.mcp.json -- Claude Code laedt dieses Projekt-Scope-File
  # automatisch, wenn "claude" aus /etc/nixos gestartet wird.
  systemd.services.mcp-config-provision = {
    description = "Provision .mcp.json for Claude Code (project scope)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -o nixos -g users -m 0644 ${mcpConfigFile} /etc/nixos/.mcp.json";
    };
  };
}
