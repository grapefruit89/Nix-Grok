# ---
# id: ""
# domain: ""          # 00|10|20|30|40|50|60|70|80|90
# status: "proposed"  # proposed | active | deprecated | template
# layer: 4            # 1-6, siehe AGENTS.md Architektur-Tabelle
# purpose: ""
# provides: []
# requires: []
# ports: []
# uid: null
# state_dir: null
# tags: []
# ---
{ config, lib, ... }:

let
  # Service-Name = Datei-Slug ohne Nummer (z.B. "sonarr" fuer 5020-sonarr.nix)
  serviceName = "";

  # Isomorphe Nummer: NNss = Domaene + Position. Identisch fuer UID + Port.
  # Beispiel: domain "50" + Position "20" (zweiter Dienst) = 5020. # z.B. 5020

  cfg = config.my.services.${serviceName} or { };
in
{
  options.my.services.${serviceName}.enable = lib.mkEnableOption "TODO Kurzbeschreibung";

  config = lib.mkIf cfg.enable {
    # UID/Port aus serviceNumber ableiten statt hart zu kodieren:
    # users.users.${serviceName}.uid = serviceNumber;
    # config.my.ports.${serviceName} = serviceNumber;

    environment.systemPackages = [ ]; # bevorzugt: pkgs.<name> statt Adhoc-Skript

    # Fabrik statt eigenem systemd-Hardening -- siehe lib/service-factory.nix
    # und modules/60-apps/SERVICE_TEMPLATE.nix fuer ein volles Beispiel.
  };
}
