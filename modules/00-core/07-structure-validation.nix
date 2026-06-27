{ lib, ... }:

let
  # ../ von modules/00-core/ aus → modules/
  modulesDir = ../.;

  allowedDirs = [
    "00-core"
    "10-network"
    "20-security"
    "30-storage"
    "40-observability"
    "50-media"
    "60-apps"
    "80-agents"
    "90-policy"
  ];

  contents = builtins.readDir modulesDir;

  # Alle Einträge, die keine Verzeichnisse sind (Dateien, Symlinks)
  nonDirEntries = lib.filterAttrs (_: t: t != "directory") contents;

  # Verzeichnisse, die nicht in allowedDirs stehen
  actualDirs = lib.filterAttrs (_: t: t == "directory") contents;
  unauthorizedDirs = lib.filter
    (name: !(lib.elem name allowedDirs))
    (lib.attrNames actualDirs);

  # Vorhandene erlaubte Verzeichnisse ohne default.nix
  dirsWithoutDefault = lib.filter
    (name: !(builtins.pathExists "${modulesDir}/${name}/default.nix"))
    (lib.attrNames actualDirs);

in
{
  assertions = [
    {
      assertion = nonDirEntries == { };
      message = ''
        modules/ enthält Dateien direkt auf der obersten Ebene — das ist nicht erlaubt.
        Alle .nix-Dateien müssen in einem der nummerierten Unterordner liegen.

        Gefundene Einträge:
        ${lib.concatMapStringsSep "\n" (name: "  modules/${name}") (lib.attrNames nonDirEntries)}
      '';
    }
    {
      assertion = unauthorizedDirs == [ ];
      message = ''
        modules/ enthält nicht erlaubte Unterordner.

        Erlaubt:
        ${lib.concatMapStringsSep "\n" (d: "  ${d}/") allowedDirs}

        Nicht erlaubt (gefunden):
        ${lib.concatMapStringsSep "\n" (d: "  ${d}/") unauthorizedDirs}

        Neuen Ordner in allowedDirs in 00-core/07-structure-validation.nix eintragen.
      '';
    }
    {
      assertion = dirsWithoutDefault == [ ];
      message = ''
        Folgende Ordner haben keine default.nix — Nix kann sie nicht importieren:

        ${lib.concatMapStringsSep "\n" (d: "  modules/${d}/default.nix fehlt") dirsWithoutDefault}
      '';
    }
  ];
}
