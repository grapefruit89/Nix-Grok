# mcp-server

Zentrale, deklarative Verwaltung der MCP-Server für Claude Code und Hermes Agent.

## Architektur

```
modules/mcp-server/default.nix  ← einzige Quelle
├── context7McpWrapper           (pkgs.writeShellScript, Nix-Store-Pfad)
│   └── liest ~/.config/context7/api_key   (User moritz)
├── Claude Code
│   └── home.activation → ~/.claude/settings.json
│       context7: store-wrapper, nixos: pkgs.mcp-nixos
└── Hermes Agent
    └── services.hermes-agent.settings.mcp_servers
        context7: pkgs.context7-mcp direkt (Key aus /var/lib/hermes/env)
        nixos:    pkgs.mcp-nixos
```

**Warum zwei context7-Definitionen?**
Hermes läuft als System-User `hermes` ohne Zugriff auf `/home/moritz/.config/`.
Deshalb bekommt Hermes den Key über `environmentFiles = ["/var/lib/hermes/env"]`
und ruft `pkgs.context7-mcp` direkt auf. Claude Code läuft als `moritz` und
nutzt den Store-Wrapper der den Key zur Laufzeit aus der Datei liest.

## Aktive Server

| Server    | Paket             | Zweck                                  | Credentials               |
|-----------|-------------------|----------------------------------------|---------------------------|
| context7  | pkgs.context7-mcp | Aktuelle Library-Doku, Code-Beispiele  | API-Key (je nach Context) |
| nixos     | pkgs.mcp-nixos    | NixOS-Optionen, Packages, HM-Optionen  | keine                     |

## Key-Management

**Claude Code (moritz):**
```bash
set-context7-api-key   # schreibt ~/.config/context7/api_key
```

**Hermes:**
`hermes-env-provision.service` kopiert `CONTEXT7_API_KEY` aus
`/var/lib/secrets/context7.env` → `/var/lib/hermes/env`
(wird beim nächsten `hermes-agent.service`-Start geladen)

## Neuen Server hinzufügen

1. Eintrag in `default.nix` ergänzen — einmal für `claudeCodeActivation` (jq-JSON),
   einmal für `services.hermes-agent.settings.mcp_servers`
2. Secrets nie inline — Datei unter `/var/lib/secrets/` oder `~/.config/<name>/`
3. `dry-build` prüfen, dann auf Anfrage `switch`

## Was entfernt wurde

| Komponente                   | Grund                                               |
|------------------------------|-----------------------------------------------------|
| `mcp-config-provision` + `.mcp.json` | Global-Scope via settings.json reicht aus   |
| `mcp-servers-nix` Flake-Input | Pakete direkt aus nixpkgs, kein Extra-Flake nötig  |
| `mcp_servers` in hermes.nix  | Hierher verschoben (war Duplikat)                   |
| `claudeCodeMcpServers` in home.nix | Hierher verschoben (war Duplikat)             |

## Gotchas

- Claude Code nutzt **Store-Pfade**, nicht `~/.local/bin/` — Store-Pfade sind immer
  verfügbar, auch direkt nach einem Rebuild ohne Login-Shell.
- Änderungen hier betreffen beide Tools gleichzeitig. Erst `dry-build`, dann Switch.
- Der `context7`-Eintrag in settings.json zeigt auf den Wrapper-Script-Store-Pfad
  (kein `/bin/`-Unterordner, da `pkgs.writeShellScript` direkt ausführbar ist).
