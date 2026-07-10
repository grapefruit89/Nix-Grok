# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Home-Manager für moritz — Grok CLI, MCP, Dotfiles
#   tags:
#     - home-manager
#     - grok
#     - mcp
# ---
{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  u = import ./profile.nix;
  cfg = osConfig.my.services.grok;
  stateDir = cfg.stateDirectory;
  context7KeyFile = "${config.home.homeDirectory}/.config/context7/api_key";
  context7Dir = "${config.home.homeDirectory}/.config/context7";
  mcpLib = import ../../mcp/lib.nix {
    inherit pkgs lib;
    user = u.name;
  };

  context7McpWrapper = pkgs.writeShellScript "context7-mcp" ''
    set -euo pipefail
    KEY_FILE="${context7KeyFile}"
    if [ ! -s "$KEY_FILE" ]; then
      echo "Context7 API-Key fehlt. Bitte: set-context7-api-key" >&2
      exit 1
    fi
    export CONTEXT7_API_KEY="$(<"$KEY_FILE")"
    exec ${pkgs.context7-mcp}/bin/context7-mcp
  '';

  setContext7ApiKey = pkgs.writeShellScript "set-context7-api-key" ''
    set -euo pipefail
    KEY_FILE="${context7KeyFile}"
    SECRETS_FILE="/var/lib/secrets/context7.env"
    mkdir -p "${context7Dir}"
    chmod 700 "${context7Dir}"

    if [ -t 0 ]; then
      read -r -s -p "Context7 API Key (Eingabe unsichtbar): " _key </dev/tty
      echo "" >/dev/tty
    else
      echo "Key von stdin (wird nicht angezeigt):" >&2
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

    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      echo "CONTEXT7_API_KEY=$(cat "$KEY_FILE")" | sudo tee "$SECRETS_FILE" >/dev/null
      sudo chmod 600 "$SECRETS_FILE"
      echo "Auch nach $SECRETS_FILE geschrieben (für Hermes)."
    else
      echo "Hinweis: /var/lib/secrets/context7.env übersprungen (sudo nicht verfügbar)."
      echo "         Für Grok reicht ~/.config/context7/api_key völlig aus."
    fi

    echo "Testen: source ~/.bashrc && grok mcp doctor context7"
  '';

  checkGrokMcp = pkgs.writeShellScript "check-grok-mcp" ''
    set -euo pipefail
    GROK="${stateDir}/bin/grok"
    if [ ! -x "$GROK" ]; then
      echo "Grok CLI nicht gefunden: $GROK" >&2
      exit 1
    fi
    if [ -f "${context7KeyFile}" ]; then
      export CONTEXT7_API_KEY="$(<"${context7KeyFile}")"
    fi
    echo "=== Grok MCP Doctor ==="
    "$GROK" mcp doctor
  '';
in
{
  home = {
    username = u.name;
    homeDirectory = "/home/${u.name}";

    packages =
      with pkgs;
      [
        htop
        git
        curl
        jq
      ]
      ++ lib.optionals cfg.enable [
        pkgs.mcp-nixos
        pkgs.mcp-server-git
      ];

    sessionVariables = lib.mkMerge [
      {
        LANG = osConfig.my.configs.locale.default;
        LC_ALL = osConfig.my.configs.locale.default;
      }
      (lib.mkIf cfg.enable {
        COLORTERM = "truecolor";
        TERM = "xterm-256color";
        GROK_INSTALLER = "nixos";
      })
    ];

    sessionPath = lib.mkIf cfg.enable [
      "${stateDir}/bin"
      "${config.home.homeDirectory}/.local/bin"
    ];

    stateVersion = "23.11";
  };

  home.file.".local/bin/set-context7-api-key" = lib.mkIf cfg.enable {
    source = setContext7ApiKey;
    executable = true;
  };

  home.file.".local/bin/context7-mcp" = lib.mkIf cfg.enable {
    source = context7McpWrapper;
    executable = true;
  };

  home.file.".local/bin/check-grok-mcp" = lib.mkIf cfg.enable {
    source = checkGrokMcp;
    executable = true;
  };

  home.file.".grok/config.toml" = lib.mkIf cfg.enable {
    text = mcpLib.grokConfigToml { homeDirectory = config.home.homeDirectory; };
    force = true;
  };

  programs.bash = lib.mkIf cfg.enable {
    enable = true;
    bashrcExtra = ''
      # Context7 API-Key für Grok MCP
      if [ -f "${context7KeyFile}" ]; then
        export CONTEXT7_API_KEY="$(<"${context7KeyFile}")"
      fi

      [[ -r "${stateDir}/completions/bash/grok.bash" ]] && source "${stateDir}/completions/bash/grok.bash"
    '';
  };

  home.activation.generateGrokCompletions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -w "${stateDir}" ] && [ -x "${stateDir}/bin/grok" ]; then
      mkdir -p "${stateDir}/completions/bash" "${stateDir}/completions/zsh"
      "${stateDir}/bin/grok" completions bash > "${stateDir}/completions/bash/grok.bash" 2>/dev/null || true
      "${stateDir}/bin/grok" completions zsh > "${stateDir}/completions/zsh/_grok" 2>/dev/null || true
    fi
  '';

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = u.git.name;
        email = u.git.email;
      };
    };
  };

  programs.home-manager.enable = true;
}
