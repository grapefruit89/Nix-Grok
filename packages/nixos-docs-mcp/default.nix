{
  lib,
  buildNpmPackage,
  fetchNpmDeps,
  nodejs_22,
}:

buildNpmPackage (_finalAttrs: {
  pname = "nixos-docs-mcp";
  version = "1.0.0";

  src = ./.;

  npmDeps = fetchNpmDeps {
    src = ./.;
    hash = "sha256-Asf9MBIoTYcmYxfuDTZfhOLxL+7iKzBv7V7XAjT1kaA=";
  };

  nodejs = nodejs_22;

  dontNpmBuild = true;

  meta = with lib; {
    description = "Read-only DuckDB MCP server for nixos_docs.db";
    license = licenses.mit;
    mainProgram = "nixos-docs-mcp";
  };
})
