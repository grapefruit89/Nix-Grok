# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Zentrale MCP-Server-Definition fuer Claude Code und Hermes Agent
#   tags:
#     - mcp
#     - claude-code
#     - hermes
# ---
#
# Architektur:
#   - mcp-nixos:  ein Pfad, beide Konsumenten (kein Key noetig)
#   - context7:   unterschiedliche Key-Quellen je Kontext
#       Claude Code (moritz):  Wrapper liest ~/.config/context7/api_key
#       Hermes (hermes-user):  pkgs.context7-mcp direkt, Key via environmentFiles
#
{ config, lib, pkgs, ... }:

let
  user          = config.my.configs.identity.user;
  userHome      = "/home/${user}";
  context7Key   = "${userHome}/.config/context7/api_key";

  # Wrapper fuer Claude Code (laeuft als moritz-User)
  context7McpWrapper = pkgs.writeShellScript "context7-mcp" ''
    set -euo pipefail
    KEY_FILE="${context7Key}"
    if [ ! -s "$KEY_FILE" ]; then
      echo "Context7 API-Key fehlt. Bitte: set-context7-api-key" >&2
      exit 1
    fi
    export CONTEXT7_API_KEY="$(<"$KEY_FILE")"
    exec ${pkgs.context7-mcp}/bin/context7-mcp
  '';

  nixosMcpBin = "${pkgs.mcp-nixos}/bin/mcp-nixos";

  # JSON fuer ~/.claude/settings.json — store-pfade, immer verfuegbar
  claudeCodeMcpJson = builtins.toJSON {
    context7 = { command = "${context7McpWrapper}"; };
    nixos    = { command = nixosMcpBin; };
  };

  # Shell-String fuer HM-Activation (aussen berechnet, kein lib-Konflikt im HM-Scope)
  claudeCodeActivation = ''
    SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    MCP=${lib.escapeShellArg claudeCodeMcpJson}
    if [ -f "$SETTINGS" ]; then
      ${pkgs.jq}/bin/jq --argjson mcp "$MCP" '.mcpServers = $mcp' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    else
      ${pkgs.jq}/bin/jq -n --argjson mcp "$MCP" '{ mcpServers: $mcp }' > "$SETTINGS"
    fi
  '';

in
{
  config = lib.mkMerge [

    # ── Claude Code: global ~/.claude/settings.json ──────────────────────────
    # HM-Activation als Funktion — lib-Argument ist HM-lib (hat lib.hm.dag)
    (lib.mkIf config.services.claude-code.enable {
      home-manager.users.${user} = { lib, ... }: {
        home.activation.claudeCodeMcpServers =
          lib.hm.dag.entryAfter [ "writeBoundary" ] claudeCodeActivation;
      };
    })

    # ── Hermes Agent: mcp_servers in settings ────────────────────────────────
    # context7-mcp direkt (kein Wrapper); Key kommt aus environmentFiles
    #   /var/lib/hermes/env <- hermes-env-provision <- /var/lib/secrets/context7.env
    (lib.mkIf config.services.hermes-agent.enable {
      services.hermes-agent.settings.mcp_servers = {
        context7 = { command = "${pkgs.context7-mcp}/bin/context7-mcp"; };
        nixos    = { command = nixosMcpBin; };
      };
    })

  ];
}
