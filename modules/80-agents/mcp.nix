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
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.my.configs.identity.user;
  userHome = "/home/${user}";
  context7Key = "${userHome}/.config/context7/api_key";
  githubMcpToken = "${userHome}/.config/github-mcp/token";
  braveSearchApiKey = "${userHome}/.config/brave-search/api_key";

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

  githubMcpWrapper = pkgs.writeShellScript "github-mcp" ''
    set -euo pipefail
    TOKEN_FILE="${githubMcpToken}"
    if [ ! -s "$TOKEN_FILE" ]; then
      echo "GitHub MCP token fehlt. Bitte: set-github-mcp-token" >&2
      exit 1
    fi
    export GITHUB_PERSONAL_ACCESS_TOKEN="$(<"$TOKEN_FILE")"
    exec ${pkgs.github-mcp-server}/bin/github-mcp-server stdio
  '';

  braveSearchMcpWrapper = pkgs.writeShellScript "brave-search-mcp" ''
    set -euo pipefail
    KEY_FILE="${braveSearchApiKey}"
    if [ ! -s "$KEY_FILE" ]; then
      echo "Brave Search API Key fehlt. Bitte: set-brave-search-api-key" >&2
      exit 1
    fi
    export BRAVE_API_KEY="$(<"$KEY_FILE")"
    exec ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-brave-search
  '';

  setGithubMcpToken = pkgs.writeShellScript "set-github-mcp-token" ''
    set -euo pipefail
    TOKEN_FILE="${githubMcpToken}"
    mkdir -p "$(dirname "$TOKEN_FILE")"
    chmod 700 "$(dirname "$TOKEN_FILE")"
    if [ -t 0 ]; then
      read -r -s -p "GitHub PAT (Eingabe unsichtbar): " _token </dev/tty
      echo "" >/dev/tty
    else
      IFS= read -r _token
    fi
    if [ -z "$_token" ]; then
      echo "Abgebrochen: leerer Token." >&2
      exit 1
    fi
    umask 077
    printf '%s' "$_token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    unset _token
    echo "Gespeichert: $TOKEN_FILE (chmod 600)"
  '';

  setBraveSearchApiKey = pkgs.writeShellScript "set-brave-search-api-key" ''
    set -euo pipefail
    KEY_FILE="${braveSearchApiKey}"
    mkdir -p "$(dirname "$KEY_FILE")"
    chmod 700 "$(dirname "$KEY_FILE")"
    if [ -t 0 ]; then
      read -r -s -p "Brave Search API Key (Eingabe unsichtbar): " _key </dev/tty
      echo "" >/dev/tty
    else
      IFS= read -r _key
    fi
    if [ -z "$_key" ]; then
      echo "Abgebrochen: leerer Key." >&2
      exit 1
    fi
    umask 077
    printf '%s' "$_key" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    unset _key
    echo "Gespeichert: $KEY_FILE (chmod 600)"
  '';

  nixosMcpBin = "${pkgs.mcp-nixos}/bin/mcp-nixos";

  # JSON fuer ~/.claude/settings.json — store-pfade, immer verfuegbar
  claudeCodeMcpJson = builtins.toJSON {
    context7 = {
      command = "${context7McpWrapper}";
    };
    nixos = {
      command = nixosMcpBin;
    };
    nixos-docs = {
      command = "${pkgs.python3}/bin/python3";
      args = [
        "/etc/nixos/scripts/nixos-docs-mcp.py"
        "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"
      ];
    };
    github = {
      command = "${githubMcpWrapper}";
    };
    "brave-search" = {
      command = "${braveSearchMcpWrapper}";
    };
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
      home-manager.users.${user} =
        { lib, ... }:
        {
          home.activation.claudeCodeMcpServers = lib.hm.dag.entryAfter [
            "writeBoundary"
          ] claudeCodeActivation;

          home.file.".local/bin/set-github-mcp-token" = {
            source = setGithubMcpToken;
            executable = true;
          };

          home.file.".local/bin/set-brave-search-api-key" = {
            source = setBraveSearchApiKey;
            executable = true;
          };
        };
    })

    # ── Hermes Agent: mcp_servers in settings ────────────────────────────────
    # context7-mcp direkt (kein Wrapper); Key kommt aus environmentFiles
    #   /var/lib/hermes/env <- hermes-env-provision <- /var/lib/secrets/context7.env
    (lib.mkIf config.services.hermes-agent.enable {
      services.hermes-agent.settings.mcp_servers = {
        context7 = {
          command = "${pkgs.context7-mcp}/bin/context7-mcp";
        };
        nixos = {
          command = nixosMcpBin;
        };
      };
    })

    # ── nixos-docs: SQLite FTS5 (kein DuckDB, keine lokale KI) ──
    {
      systemd = {
        services.nixos-docs-indexer = {
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

        timers.nixos-docs-indexer = {
          description = "nixos-docs Indexer Timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            Persistent = true;
          };
        };
      };
    }
  ];
}
