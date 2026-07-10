# mcp/ — Zentrale MCP-Server (alle Agenten)

> **Eine Quelle:** `mcp/lib.nix` definiert alle Server.  
> **Verdrahtung:** `mcp/default.nix` (NixOS-Modul, importiert via `modules/80-agents/mcp.nix`).

## Server

| Server | Paket/Script | Credentials |
|--------|--------------|-------------|
| `context7` | `pkgs.context7-mcp` | `~/.config/context7/api_key` |
| `nixos` | `pkgs.mcp-nixos` | keine |
| `nixos-docs` | `scripts/nixos-docs-mcp.py` + SQLite FTS5 | keine |
| `github` | `pkgs.github-mcp-server` | `~/.config/github-mcp/token` |
| `brave-search` | `npx @modelcontextprotocol/server-brave-search` | `~/.config/brave-search/api_key` |
| `exa` | `https://mcp.exa.ai/mcp` (nur Hermes) | keine |

## Wo aktiv

| Agent | Mechanismus | Datei |
|-------|-------------|-------|
| **Claude Code (global)** | HM-Activation | `~/.claude/settings.json` |
| **Claude Code (Projekt)** | systemd oneshot | `/etc/nixos/.mcp.json` |
| **Grok CLI** | HM `config.toml` | `~/.grok/config.toml` |
| **Hermes** | `mcp_servers` | `mcp/lib.nix` → hermes.nix |
| **Grok Build (Cursor)** | xAI-eingebaute Remote-MCP | siehe unten |

### Grok Build vs. Repo-MCP

**Grok Build** (diese IDE-Session) bekommt MCP von xAI/Cursor — nicht aus diesem Repo:

- `nixos`, `grok_com_github`, `cloudflare` (eingebaut)
- **Kein** `nixos-docs`, `context7`, `brave-search` (stdio-Server aus Nix)

Für volle Parität: **Grok CLI** (`grok mcp doctor`) oder **Claude Code** aus `/etc/nixos` nutzen.

## Credentials

```bash
set-context7-api-key      # ~/.config/context7/api_key
set-github-mcp-token      # ~/.config/github-mcp/token
set-brave-search-api-key  # ~/.config/brave-search/api_key
```

## Neuen Server hinzufügen

1. Eintrag in `mcp/lib.nix` (`claudeServers`, `hermesServers`, `grokConfigToml`)
2. `sudo nixos-rebuild switch`
3. `mcp/README.md` aktualisieren