# mcp/

Zentrale, **modellunabhängige** MCP-Server-Definitionen. Ein MCP-Server weiss nichts vom
LLM dahinter — jeder MCP-fähige Client (Claude Code, Hermes, Grok, etc.) kann sich
unabhängig vom genutzten Modell hier dranhängen.

Konvention (analog zu modules/):
- Eine Datei pro MCP-Server: `mcp/<name>.nix`
- Jeder Server deklariert `options.my.mcp.<name>.enable` + Port/Pfad-Optionen
- Aggregator: `mcp/default.nix` importiert alle Server-Module

Migriert aus users/moritz/home.nix (vorher Grok-spezifisch verdrahtet):
- nixos_docs (DuckDB-Wissens-Index, packages/nixos-docs-mcp)
- context7 (extern, API-Key in /var/lib/secrets/context7.env)
- mcp-nixos (nixpkgs: pkgs.mcp-nixos)
- mcp-server-git (nixpkgs: pkgs.mcp-server-git)

TODO: Server-Module hier ausimplementieren, dann modules/dev/claude-code.nix und
modules/60-apps/hermes.nix darauf verweisen lassen statt jeweils eigene Pfade zu hardcoden.
