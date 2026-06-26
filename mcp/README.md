# mcp/ -- Modellunabhaengige MCP-Server, deklarativ verwaltet

Framework: `natsukium/mcp-servers-nix` (Flake-Input, siehe `flake.nix`).
Erzeugt eine fertige `.mcp.json` (Claude-Code-Projekt-Scope), automatisch
nach `/etc/nixos/.mcp.json` provisioniert (`mcp/default.nix`).

## Aktuell aktiv

| Server | Modul-Name | Zweck | Credentials |
|---|---|---|---|
| context7 | `programs.context7` | Aktuelle Library-Doku/Code-Beispiele | `envFile = /var/lib/secrets/context7.env` |
| mcp-nixos | `programs.nixos` | NixOS-Pakete/Optionen/Home-Manager ohne Halluzinationen | keine |

## Neuen Server hinzufuegen

1. Pruefen, ob das Modul schon in `mcp-servers-nix` existiert:
   https://github.com/natsukium/mcp-servers-nix/tree/main/modules/servers
2. In `flake.nix`, im `mcpConfigFile`-Block (im `let` der `outputs`-Funktion),
   einen weiteren `programs.<name> = { enable = true; ... };` Eintrag ergaenzen.
3. Secrets NIEMALS inline -- `envFile` auf eine Datei unter `/var/lib/secrets/`
   zeigen lassen, nie den Wert direkt in die `.nix`-Datei schreiben.
4. `nixos-rebuild dry-build --impure` pruefen, dann committen.
5. Existiert das Modul dort nicht: als "custom server" im selben Block per
   `settings.mcpServers.<name> = { command = ...; args = [...]; };` ergaenzen
   (Framework unterstuetzt das laut Doku zusaetzlich zu den fertigen Modulen).

## Geplant / noch nicht angegangen

- `codemcp` (ezyang/codemcp, Fork sielicki/codemcp): groesstenteils redundant
  zu Claude Code CLI selbst (Datei-Edits, Git-Commits, Tests -- das kann
  Claude Code schon nativ). Einziger Mehrwert: Remote-Zugriff via
  `codemcp serve --host <ip>` fuer Claude DESKTOP (nicht CLI) von einem
  anderen Geraet aus. Nur einbauen, wenn das konkret gebraucht wird.
- Weitere Kandidaten aus der Tier-Liste: Git-MCP, Filesystem-MCP (whitelisted
  auf `/etc/nixos`), Sequential-Thinking -- bei Bedarf nachziehen.
