# ---
# meta:
#   layer: 5
#   role: aggregator
#   purpose: Zentrale MCP-Server — alle Agenten, eine Quelle (mcp/lib.nix)
#   docs:
#     - mcp/README.md
#   tags:
#     - mcp
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.my.configs.identity.user;
  mcp = import ./lib.nix { inherit pkgs lib user; };
  claudeJson = builtins.toJSON mcp.claudeServers;
  mcpConfigFile = pkgs.writeText "nixos-mcp.json" claudeJson;

  claudeCodeActivation = ''
    SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    MCP=${lib.escapeShellArg claudeJson}
    if [ -f "$SETTINGS" ]; then
      ${pkgs.jq}/bin/jq --argjson mcp "$MCP" '.mcpServers = $mcp' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    else
      ${pkgs.jq}/bin/jq -n --argjson mcp "$MCP" '{ mcpServers: $mcp }' > "$SETTINGS"
    fi
  '';
in
{
  options.my.mcp = {
    enable = lib.mkEnableOption "Zentrale MCP-Server (Claude, Grok CLI, Hermes, .mcp.json)";
    claudeServers = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "MCP-Server-Attrset für Claude Code / .mcp.json";
    };
    hermesServers = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "MCP-Server für Hermes Agent";
    };
  };

  config = lib.mkIf config.my.mcp.enable {
    my.mcp.claudeServers = mcp.claudeServers;
    my.mcp.hermesServers = mcp.hermesServers;

    systemd.services.mcp-config-provision = {
      description = "Provision /etc/nixos/.mcp.json für Claude Code (Projekt-Scope)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -o ${user} -g users -m 0644 ${mcpConfigFile} /etc/nixos/.mcp.json";
      };
    };

    home-manager.users.${user} =
      { lib, ... }:
      lib.mkMerge [
        {
          home.file.".local/bin/github-mcp".source = mcp.githubMcpWrapper;
          home.file.".local/bin/github-mcp".executable = true;
          home.file.".local/bin/brave-search-mcp".source = mcp.braveSearchMcpWrapper;
          home.file.".local/bin/brave-search-mcp".executable = true;
          home.file.".local/bin/nixos-docs-mcp".source = mcp.nixosDocsMcpWrapper;
          home.file.".local/bin/nixos-docs-mcp".executable = true;
          home.file.".local/bin/set-github-mcp-token".source = mcp.setGithubMcpToken;
          home.file.".local/bin/set-github-mcp-token".executable = true;
          home.file.".local/bin/set-brave-search-api-key".source = mcp.setBraveSearchApiKey;
          home.file.".local/bin/set-brave-search-api-key".executable = true;
        }
        (lib.mkIf config.services.claude-code.enable {
          home.activation.claudeCodeMcpServers = lib.hm.dag.entryAfter [
            "writeBoundary"
          ] claudeCodeActivation;
        })
      ];

    services.hermes-agent.settings.mcp_servers = lib.mkIf config.services.hermes-agent.enable mcp.hermesServers;
  };
}
