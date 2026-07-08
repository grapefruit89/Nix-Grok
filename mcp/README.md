# mcp/ -- Modellunabhaengige MCP-Server, deklarativ verwaltet

## Aktive Server

| Server | Paket | Zweck | Credentials |
|---|---|---|---|
| `context7` | `pkgs.context7-mcp` | Aktuelle Library-Doku/Code-Beispiele | `~/.config/context7/api_key` |
| `mcp-nixos` | `pkgs.mcp-nixos` | NixOS-Pakete/Optionen/HM ohne Halluzinationen | keine |
| `github` | `pkgs.github-mcp-server` | Issues/PRs/Code-Suche auf GitHub | `~/.config/github-mcp/token` |
| `brave-search` | `npx @modelcontextprotocol/server-brave-search` | Web-Suche via Brave API | `~/.config/brave-search/api_key` |

**Hinweis brave-search:** Kein Nixpkgs-Paket -- verwendet `npx` (`pkgs.nodejs_22`).
Abweichung vom "kein npx"-Prinzip; geflaggert bis ein nativer Nixpkgs-Wrapper existiert.

## Wo die Server aktiv sind

| Scope | Datei / Mechanismus | Status |
|---|---|---|
| **Claude Code global** | `~/.claude/settings.json` via `home.activation.claudeCodeMcpServers` in `users/moritz/home.nix` | **aktiv** |
| **Claude Code Projekt** | `/etc/nixos/.mcp.json` via `systemd.services.mcp-config-provision` (dieses Modul) | **nicht verdrahtet** -- `mcp/default.nix` wird noch nicht importiert |
| **Hermes** | `services.hermes-agent.settings.mcp_servers` in `modules/60-apps/hermes.nix` | aktiv (context7, nixos) |

### Credentials setzen

```bash
set-context7-api-key        # ~/.config/context7/api_key
set-github-mcp-token        # ~/.config/github-mcp/token
set-brave-search-api-key    # ~/.config/brave-search/api_key
```

## Architektur: Global-Scope via home.activation

**Global-Scope** (`~/.claude/settings.json`): `home.activation.claudeCodeMcpServers`
in `users/moritz/home.nix` merged nach jedem `nixos-rebuild switch` die `mcpServers`-
Sektion per `jq`. Greift in jeder Claude-Code-Session.

**Projekt-Scope** (`/etc/nixos/.mcp.json`): Noch nicht aktiv. `mcp/default.nix`
existiert, ist aber nirgendwo importiert und `mcp-config-provision.service` laeuft nicht.
Aktivieren: In `flake.nix` als NixOS-Modul einbinden.

## Neuen Server hinzufuegen

1. `nix search nixpkgs mcp-server` -- oft ist das Paket direkt verfuegbar
2. In `users/moritz/home.nix`:
   - Wrapper-Script im `let`-Block definieren (liest Secret aus `~/.config/<name>/api_key`)
   - `home.file.".local/bin/<name>"` Eintrag hinzufuegen
   - In `claudeCodeMcpServers` activation: `--arg name ...` und JSON-Eintrag ergaenzen
   - Setup-Script `set-<name>-token` analog zu `set-github-mcp-token`
3. Secrets nie inline in settings.json oder Git -- nur in `~/.config/<name>/api_key`
4. `sudo scripts/nixos-rebuild-safe.sh` (dry-build), dann switch

## Kandidaten fuer spaeter

- **Sequential Thinking**: Marginaler Mehrwert fuer moderne Modelle.
- **Filesystem MCP**: Fuer Claude Code redundant (native Read/Write/Edit-Tools).
