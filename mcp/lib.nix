# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Zentrale MCP-Server-Definitionen — Claude, Grok CLI, Hermes
#   docs:
#     - mcp/README.md
#   tags:
#     - mcp
# ---
# Zentrale MCP-Server-Definitionen — eine Quelle für alle Agenten.
# Siehe mcp/README.md
{
  pkgs,
  lib,
  user,
}:
let
  userHome = "/home/${user}";
  context7Key = "${userHome}/.config/context7/api_key";
  githubMcpToken = "${userHome}/.config/github-mcp/token";
  braveSearchApiKey = "${userHome}/.config/brave-search/api_key";
  nixosDocsDb = "/var/lib/nixos-docs-mcp/nixos_docs.sqlite";
  nixosMcpBin = "${pkgs.mcp-nixos}/bin/mcp-nixos";
  python3 = "${pkgs.python3}/bin/python3";
  nixosDocsScript = "/etc/nixos/scripts/nixos-docs-mcp.py";
  exaMcpUrl = "https://mcp.exa.ai/mcp";

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
    export PATH="${pkgs.nodejs_22}/bin:$PATH"
    exec ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-brave-search
  '';

  nixosDocsMcpWrapper = pkgs.writeShellScript "nixos-docs-mcp" ''
    set -euo pipefail
    DB="${nixosDocsDb}"
    if [ ! -r "$DB" ]; then
      echo "nixos_docs.sqlite fehlt unter $DB — systemctl start nixos-docs-indexer.service" >&2
      exit 1
    fi
    exec ${python3} ${nixosDocsScript} "$DB"
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

  # Claude Code ~/.claude/settings.json und /etc/nixos/.mcp.json
  claudeServers = {
    context7 = {
      command = "${context7McpWrapper}";
    };
    nixos = {
      command = nixosMcpBin;
    };
    nixos-docs = {
      command = python3;
      args = [
        nixosDocsScript
        nixosDocsDb
      ];
    };
    github = {
      command = "${githubMcpWrapper}";
    };
    brave-search = {
      command = "${braveSearchMcpWrapper}";
    };
    exa = {
      url = exaMcpUrl;
    };
  };

  # Hermes agent (stdio + remote URL)
  hermesServers = {
    context7 = {
      command = "${context7McpWrapper}";
    };
    nixos = {
      command = nixosMcpBin;
    };
    nixos-docs = {
      command = python3;
      args = [
        nixosDocsScript
        nixosDocsDb
      ];
    };
    exa = {
      url = exaMcpUrl;
    };
  };

  # Grok CLI ~/.grok/config.toml — gleiche Server wie Claude
  grokServerNames = [
    "context7"
    "nixos"
    "nixos_docs"
    "github"
    "brave-search"
    "exa"
  ];

in
{
  inherit
    context7McpWrapper
    githubMcpWrapper
    braveSearchMcpWrapper
    nixosDocsMcpWrapper
    setGithubMcpToken
    setBraveSearchApiKey
    nixosMcpBin
    nixosDocsDb
    claudeServers
    hermesServers
    grokServerNames
    userHome
    ;

  grokConfigToml =
    { homeDirectory }:
    let
      cmd =
        name: value:
        if value ? url then
          ''
            [mcp_servers.${name}]
            url = "${value.url}"
            enabled = true

          ''
        else if value ? args then
          ''
            [mcp_servers.${name}]
            command = "${value.command}"
            args = [ ${lib.concatStringsSep " " (map (a: ''"${a}"'') value.args)} ]
            enabled = true

          ''
        else
          ''
            [mcp_servers.${name}]
            command = "${value.command}"
            enabled = true

          '';
      grokMap = {
        context7 = {
          command = "${homeDirectory}/.local/bin/context7-mcp";
        };
        nixos = {
          command = nixosMcpBin;
        };
        nixos_docs = {
          command = "${homeDirectory}/.local/bin/nixos-docs-mcp";
        };
        github = {
          command = "${homeDirectory}/.local/bin/github-mcp";
        };
        "brave-search" = {
          command = "${homeDirectory}/.local/bin/brave-search-mcp";
        };
        exa = {
          url = exaMcpUrl;
        };
      };
    in
    ''
      [cli]
      auto_update = false
      installer = "nixos"

      [features]
      telemetry = false

    ''
    + lib.concatMapStrings (n: cmd n grokMap.${n}) grokServerNames;
}
