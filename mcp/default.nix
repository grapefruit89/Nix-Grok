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
  userHome = "/home/${user}";
  mcp = import ./lib.nix { inherit pkgs lib user; };
  claudeServersJson = builtins.toJSON mcp.claudeServers;
  mcpProjectJson = builtins.toJSON { mcpServers = mcp.claudeServers; };
  mcpConfigFile = pkgs.writeText "nixos-mcp.json" mcpProjectJson;
  grokConfigFile = pkgs.writeText "grok-mcp-config.toml" (
    mcp.grokConfigToml { homeDirectory = userHome; }
  );

  claudeCodeActivation = ''
    SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    MCP=${lib.escapeShellArg claudeServersJson}
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

    systemd.services.grok-config-provision = {
      description = "Provision /etc/nixos/.grok/config.toml für Grok CLI (Projekt-Scope)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -o ${user} -g users -m 0644 ${grokConfigFile} /etc/nixos/.grok/config.toml";
      };
    };

    systemd.tmpfiles.rules = [
      "d /etc/nixos/.grok 0755 ${user} users -"
    ];

    home-manager.users.${user} =
      {
        config,
        osConfig,
        lib,
        ...
      }:
      lib.mkMerge [
        {
          home.file.".local/bin/context7-mcp".source = mcp.context7McpWrapper;
          home.file.".local/bin/context7-mcp".executable = true;
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
          home.file.".grok/config.toml" = {
            text = mcp.grokConfigToml { homeDirectory = config.home.homeDirectory; };
            force = true;
          };
        }
        (lib.mkIf osConfig.services.claude-code.enable {
          home.activation.claudeCodeMcpServers = lib.hm.dag.entryAfter [
            "writeBoundary"
          ] claudeCodeActivation;
        })
      ];

    services.hermes-agent.settings.mcp_servers = lib.mkIf config.services.hermes-agent.enable mcp.hermesServers;
  };
}
