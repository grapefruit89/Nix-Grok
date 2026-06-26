# ---
# id: "nixmeta-ban"
# domain: "00"
# status: "active"
# layer: 4
# purpose: "Build-Time-Assertion: NIXMETA (# !type Marker) ist permanent verboten"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["security", "hygiene", "meta"]
# ---
{ lib, ... }:

let
  repoRoot = ../../.;

  # Rekursiv alle .nix-Dateien einsammeln (Git/stage-nixos ausgenommen).
  collectNixFiles =
    dir:
    let
      entries = builtins.readDir dir;
      names = builtins.attrNames entries;
    in
    lib.concatMap (
      name:
      let
        path = dir + "/${name}";
        type = entries.${name};
      in
      if type == "directory" && name != ".git" && name != "stage-nixos" then
        collectNixFiles path
      else if type == "regular" && lib.hasSuffix ".nix" name && name != "0020-nixmeta-ban.nix" then
        [ path ]
      else
        [ ]
    ) names;

  nixmetaPattern = builtins.match "[ \t]*#[ \t]*![a-z]+.*";

  fileHasNixmeta =
    path:
    let
      content = builtins.readFile path;
      lines = lib.splitString "\n" content;
    in
    lib.any (line: nixmetaPattern line != null) lines;

  offenders = lib.filter fileHasNixmeta (collectNixFiles repoRoot);
in
{
  assertions = [
    {
      assertion = offenders == [ ];
      message = "[NIXMETA-BAN] Verbotene '# !type'-Marker in: ${lib.concatStringsSep ", " (map toString offenders)} -- siehe AGENTS.md.";
    }
  ];
}
