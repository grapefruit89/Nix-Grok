# mcp/ -- Modellunabhaengige MCP-Server, deklarativ verwaltet

## Aktive Server

| Server | Nixpkgs-Paket | Zweck | Credentials |
|---|---|---|---|
| `context7` | `pkgs.context7-mcp` (3.0.0) | Aktuelle Library-Doku/Code-Beispiele | `~/.config/context7/api_key` (moritz) |
| `mcp-nixos` | `pkgs.mcp-nixos` (2.4.3) | NixOS-Pakete/Optionen/HM ohne Halluzinationen | keine |

Beide Pakete kommen aus nixpkgs -- kein `npx`, kein Netzwerkzugriff beim Start.

## Wo die Server aktiv sind

| Scope | Datei / Mechanismus |
|---|---|
| **Claude Code global** | `~/.claude/settings.json` via `home.activation.claudeCodeMcpServers` in `users/moritz/home.nix` |
| **Claude Code Projekt** | `/etc/nixos/.mcp.json` via `systemd.services.mcp-config-provision` (this module); nur aktiv wenn `claude` aus `/etc/nixos` gestartet wird |
| **Hermes** | `services.hermes-agent.settings.mcp_servers` in `modules/60-apps/hermes.nix`; `CONTEXT7_API_KEY` kommt aus `/var/lib/hermes/env` |

### Context7-Key setzen

```bash
set-context7-api-key   # schreibt ~/.config/context7/api_key (moritz)
                       # kopiert optional nach /var/lib/secrets/context7.env
                       # hermes-env-provision liest von dort nach /var/lib/hermes/env
```

## Architektur: Zwei Ebenen

**Projekt-Scope** (`/etc/nixos/.mcp.json`): Erzeugt durch `mcp-servers-nix.lib.mkConfig`
in `flake.nix`. Greift nur wenn `claude` aus `/etc/nixos` gestartet wird.

**Global-Scope** (`~/.claude/settings.json`): Gesetzt durch `home.activation` in
`users/moritz/home.nix`. Greift in jeder Claude-Code-Session.

Beide Scopes zeigen auf dieselben Binaries aus dem Nix-Store.

## Neuen Server hinzufuegen

1. `nix search nixpkgs mcp-server` -- oft ist das Paket direkt verfuegbar
2. In `users/moritz/home.nix`:
   - Wrapper oder direkten Store-Pfad im `let`-Block definieren
   - In `claudeCodeMcpServers` activation: neuen Eintrag in das `jq -n '{...}'` einbauen
3. Fuer Projekt-Scope: in `flake.nix` im `mcpConfigFile`-Block erganzen
4. Secrets nie inline -- Datei unter `/var/lib/secrets/` oder `~/.config/<name>/api_key`
5. `nixos-rebuild dry-build --impure` pruefen, dann `switch`

## Kandidaten fuer spaeter

- **GitHub MCP** (`pkgs.github-mcp-server`, v1.0.5): Benoetigt `GITHUB_PERSONAL_ACCESS_TOKEN`.
  Sinnvoll wenn Issues/PRs regelmaessig im Chat bearbeitet werden.
- **Filesystem MCP**: Fuer Claude Code redundant (native Read/Write/Edit-Tools).
  Fuer Agenten ohne native Datei-Tools potenziell nuetzlich.
- **Sequential Thinking**: Marginaler Mehrwert fuer moderne Modelle.
