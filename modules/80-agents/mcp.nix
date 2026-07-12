# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Zentrale MCP-Server-Definition fuer Claude Code, Grok und Hermes Agent
#   tags:
#     - mcp
#     - claude-code
#     - hermes
#     - nixos-docs
# ---
#
# Architektur:
#   - mcp-nixos:     nixpkgs live (Optionen, Pakete)
#   - nixos-docs:    nixos_docs.sqlite FTS5 (ADRs, Module, error_pattern)
#   - context7:      externe Doku — Key aus ~/.config/context7/api_key
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  rebuildGuard = import ../../lib/rebuild-guard.nix { inherit lib; };
  user = config.my.configs.identity.user;
  userHome = "/home/${user}";
  context7Key = "${userHome}/.config/context7/api_key";
  githubMcpToken = "${userHome}/.config/github-mcp/token";
  braveSearchApiKey = "${userHome}/.config/brave-search/api_key";

  nixosMcpBin = "${pkgs.mcp-nixos}/bin/mcp-nixos";
  nixosDocsDb = "/var/lib/nixos-docs-mcp/nixos_docs.sqlite";
  nixosDocsMcpScript = "/etc/nixos/scripts/nixos-docs-mcp.py";

  nixosDocsMcpWrapper = pkgs.writeShellScript "nixos-docs-mcp" ''
    set -euo pipefail
    exec ${pkgs.python3}/bin/python3 ${nixosDocsMcpScript} ${nixosDocsDb}
  '';

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

  mcpWrappers = {
    "context7-mcp" = context7McpWrapper;
    "github-mcp" = githubMcpWrapper;
    "brave-search-mcp" = braveSearchMcpWrapper;
    "nixos-docs-mcp" = nixosDocsMcpWrapper;
  };

  claudeCodeMcpJson = builtins.toJSON {
    context7 = {
      command = "${context7McpWrapper}";
    };
    nixos = {
      command = nixosMcpBin;
    };
    "nixos-docs" = {
      command = "${nixosDocsMcpWrapper}";
    };
    github = {
      command = "${githubMcpWrapper}";
    };
    "brave-search" = {
      command = "${braveSearchMcpWrapper}";
    };
  };

  repoMcpJson = builtins.toJSON {
    mcpServers = {
      context7 = {
        command = "${context7McpWrapper}";
      };
      nixos = {
        command = nixosMcpBin;
      };
      "nixos-docs" = {
        command = "${nixosDocsMcpWrapper}";
      };
      github = {
        command = "${githubMcpWrapper}";
      };
      "brave-search" = {
        command = "${braveSearchMcpWrapper}";
      };
    };
  };

  grokMcpConfigToml = pkgs.writeText "grok-mcp-config.toml" ''
    [cli]
    auto_update = false
    installer = "nixos"

    [features]
    telemetry = false

    [mcp_servers.context7]
    command = "${context7McpWrapper}"
    enabled = true

    [mcp_servers.nixos]
    command = "${nixosMcpBin}"
    enabled = true

    [mcp_servers.nixos-docs]
    command = "${nixosDocsMcpWrapper}"
    enabled = true

    [mcp_servers.github]
    command = "${githubMcpWrapper}"
    enabled = true

    [mcp_servers.brave-search]
    command = "${braveSearchMcpWrapper}"
    enabled = true

    [ui]
    permission_mode = "always-approve"
    theme = "grokday"
    yolo = false
    compact_mode = false
    max_thoughts_width = 120
    fork_secondary_model = "grok-build"
  '';

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

  mcpAgentsEnabled = config.services.claude-code.enable || config.my.services.grok.enable;
in
{
  config = lib.mkMerge [
    (lib.mkIf mcpAgentsEnabled {
      home-manager.users.${user} =
        { lib, ... }:
        {
          home.file = lib.mkMerge [
            (lib.mapAttrs' (name: wrapper: {
              name = ".local/bin/${name}";
              value = {
                source = wrapper;
                executable = true;
              };
            }) mcpWrappers)
            {
              ".local/bin/set-github-mcp-token" = {
                source = setGithubMcpToken;
                executable = true;
              };
              ".local/bin/set-brave-search-api-key" = {
                source = setBraveSearchApiKey;
                executable = true;
              };
            }
            (lib.mkIf config.my.services.grok.enable {
              ".grok/config.toml" = {
                source = grokMcpConfigToml;
                force = true;
              };
            })
          ];

          home.activation.claudeCodeMcpServers = lib.mkIf config.services.claude-code.enable (
            lib.hm.dag.entryAfter [ "writeBoundary" ] claudeCodeActivation
          );
        };
    })

    (lib.mkIf config.services.hermes-agent.enable {
      services.hermes-agent.settings.mcp_servers = {
        context7 = {
          command = "${pkgs.context7-mcp}/bin/context7-mcp";
        };
        nixos = {
          command = nixosMcpBin;
        };
        "nixos-docs" = {
          command = "${nixosDocsMcpWrapper}";
        };
      };
    })

    {
      systemd.tmpfiles.rules = [
        "d /var/lib/nixos-docs-mcp 0750 root root -"
      ];

      system.activationScripts.nixosDocsMcpJson = lib.mkIf mcpAgentsEnabled ''
        MCP_JSON=${lib.escapeShellArg repoMcpJson}
        ${pkgs.jq}/bin/jq . <<< "$MCP_JSON" > /etc/nixos/.mcp.json
        chmod 644 /etc/nixos/.mcp.json
      '';

      systemd.services.nixos-docs-indexer = {
        description = "Indexiert /etc/nixos in nixos_docs.sqlite (FTS + Meta + Chunks + module_import)";
        after = [ "local-fs.target" ];
        wantedBy = [ "multi-user.target" ];
        startLimitIntervalSec = 0;
        startLimitBurst = 0;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.python3}/bin/python3 /etc/nixos/scripts/index-nix-files.py";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadOnlyPaths = [ "/etc/nixos" ];
          ReadWritePaths = [ "/var/lib/nixos-docs-mcp" ];
        };
      };

      systemd.paths.nixos-docs-indexer-switch = {
        description = "nixos-docs Indexer nach nixos-rebuild switch";
        wantedBy = [ "multi-user.target" ];
        unitConfig = lib.mkMerge [
          rebuildGuard.pathUnitGuard
          {
            TriggerLimitBurst = 1;
            TriggerLimitIntervalSec = "2min";
          }
        ];
        pathConfig = {
          PathExists = "/run/current-system";
          PathChanged = "/run/current-system";
          Unit = "nixos-docs-indexer.service";
          MakeDirectory = false;
        };
      };

      systemd.paths.nixos-docs-indexer-flake = {
        description = "nixos-docs Indexer bei flake.lock-Änderung";
        wantedBy = [ "multi-user.target" ];
        unitConfig = lib.mkMerge [
          rebuildGuard.pathUnitGuard
          {
            TriggerLimitBurst = 1;
            TriggerLimitIntervalSec = "5min";
          }
        ];
        pathConfig = {
          PathExists = "/etc/nixos/flake.lock";
          PathChanged = "/etc/nixos/flake.lock";
          Unit = "nixos-docs-indexer.service";
          MakeDirectory = false;
        };
      };
    }
  ];
}
