# ---
# meta:
#   layer: 4
#   role: user
#   purpose: Home-Manager — Grok CLI, MCP, Dotfiles
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
  cfg = osConfig.my.services.grok;
  stateDir = cfg.stateDirectory;
  context7KeyFile = "${config.home.homeDirectory}/.config/context7/api_key";
  context7Dir = "${config.home.homeDirectory}/.config/context7";
  nixosDocsDbDir = "${config.home.homeDirectory}/.local/share/nix-grok";
  nixosDocsDbFile = "${nixosDocsDbDir}/nixos_docs.db";
  nixosDocsMcp = pkgs.callPackage ../../packages/nixos-docs-mcp { };
  nixConfigDirs = [
    "/etc/nixos"
    "/home/nixos"
  ];

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

    # Optional: systemweit für Hermes (Stufe 7) — moritz hat kein Passwort, sudo schlägt fehl → OK
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

  nixosDocsMcpWrapper = pkgs.writeShellScript "nixos-docs-mcp" ''
    set -euo pipefail
    export HOME="${config.home.homeDirectory}"
    cd "$HOME"
    export NIXOS_DOCS_DB="${nixosDocsDbFile}"
    mkdir -p "${nixosDocsDbDir}"
    if [ ! -s "$NIXOS_DOCS_DB" ]; then
      echo "nixos_docs.db fehlt. Bitte: sync-nixos-docs-db" >&2
      exit 1
    fi
    exec ${nixosDocsMcp}/bin/nixos-docs-mcp
  '';

  syncNixosDocsDb = pkgs.writeShellScript "sync-nixos-docs-db" ''
    set -euo pipefail
    DEST="${nixosDocsDbFile}"
    mkdir -p "${nixosDocsDbDir}"

    if [ -n "''${1:-}" ]; then
      SRC="''${1}"
    elif [ -r /mnt/usbinspect/NixOS/nixos_docs.db ]; then
      SRC=/mnt/usbinspect/NixOS/nixos_docs.db
    elif [ -r /home/nixos/data/nixos_docs.db ]; then
      SRC=/home/nixos/data/nixos_docs.db
    else
      echo "Keine Quelle gefunden. Nutzung: sync-nixos-docs-db [pfad/zur/nixos_docs.db]" >&2
      exit 1
    fi

    if [ -r "$SRC" ]; then
      install -m 0644 "$SRC" "$DEST"
    elif command -v sudo >/dev/null 2>&1 && sudo -n test -r "$SRC" 2>/dev/null; then
      sudo install -o "$(id -un)" -g "$(id -gn)" -m 0644 "$SRC" "$DEST"
    else
      echo "Quelle nicht lesbar: $SRC" >&2
      echo "Tipp: sudo install -o moritz -g users -m 0644 <quelle> $DEST" >&2
      exit 1
    fi
    echo "nixos_docs.db → $DEST ($(du -h "$DEST" | cut -f1))"
    echo "Hinweis: Datei ist DuckDB (nicht SQLite). GEMINI.md-SQL-Dump ist älteres Format."
    echo "Testen: source ~/.bashrc && grok mcp doctor nixos_docs"
  '';

  checkGrokMcp = pkgs.writeShellScript "check-grok-mcp" ''
    set -euo pipefail
    GROK="${stateDir}/bin/grok"
    if [ ! -x "$GROK" ]; then
      echo "Grok CLI nicht gefunden: $GROK" >&2
      exit 1
    fi
    # Context7 braucht API-Key in der Shell
    if [ -f "${context7KeyFile}" ]; then
      export CONTEXT7_API_KEY="$(<"${context7KeyFile}")"
    fi
    echo "=== Grok MCP Doctor ==="
    "$GROK" mcp doctor
  '';
in
{
  home = {
    username = "moritz";
    homeDirectory = "/home/moritz";

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
        nixosDocsMcp
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

  home.file.".local/bin/nixos-docs-mcp" = lib.mkIf cfg.enable {
    source = nixosDocsMcpWrapper;
    executable = true;
  };

  home.file.".local/bin/sync-nixos-docs-db" = lib.mkIf cfg.enable {
    source = syncNixosDocsDb;
    executable = true;
  };

  home.file.".grok/config.toml" = lib.mkIf cfg.enable {
    text = ''
      [cli]
      auto_update = false
      installer = "nixos"

      [features]
      telemetry = false

      # Context7 — stdio, Key: set-context7-api-key → https://context7.com/dashboard
      [mcp_servers.context7]
      command = "${config.home.homeDirectory}/.local/bin/context7-mcp"
      enabled = true

      # mcp-nixos — Live-Daten: Pakete, Optionen, HM, Flakes, cache.nixos.org
      # https://mcp-nixos.io | nixpkgs: pkgs.mcp-nixos
      [mcp_servers.nixos]
      command = "${pkgs.mcp-nixos}/bin/mcp-nixos"
      enabled = true

      # nixos_docs — Wissens-SSoT-Index (DuckDB) vom USB/nix-hermes
      # Quelle: sync-nixos-docs-db | Nix-Dateien bleiben autoritativ (GEMINI.md)
      [mcp_servers.nixos_docs]
      command = "${config.home.homeDirectory}/.local/bin/nixos-docs-mcp"
      enabled = true

      # Git — optional; normales git reicht meist
      [mcp_servers.git]
      command = "${pkgs.mcp-server-git}/bin/mcp-server-git"
      args = [ ${lib.concatStringsSep ", " (map (d: ''"${d}"'') nixConfigDirs)} ]
      enabled = false
    '';
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

  # MCP-Server: siehe modules/mcp-server/default.nix


  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "moritz";
        email = "moritz@example.com";
      };
    };
  };

  programs.home-manager.enable = true;
}
