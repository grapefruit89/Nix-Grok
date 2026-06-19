{ config, lib, pkgs, ... }:

let
  cfg = config.my.hardware.scanner;
  cfgPaperless = config.my.services.paperless;
in
{
  options.my.hardware.scanner = {
    enable = lib.mkEnableOption "Universal SANE Scanner Auto-Trigger";
  };

  config = lib.mkIf cfg.enable {
    # 1. Aktiviere SANE
    hardware.sane = {
      enable = true;
      extraBackends = [ pkgs.sane-backends ];
    };

    # 2. Füge den paperless User der scanner Gruppe hinzu, falls paperless aktiviert ist
    users.users.paperless.extraGroups = lib.mkIf cfgPaperless.enable [ "scanner" "lp" ];

    # 3. Die Udev-Regeln für Scanner!
    # Regel A: Fallback/Direkt-Erkennung für Canon CanoScan LiDE 220
    # Regel B: Universelle Erkennung für JEDEN SANE-unterstützten Scanner
    services.udev.extraRules = lib.mkIf cfgPaperless.enable ''
      ACTION=="bind", ENV{DEVTYPE}=="usb_device", ENV{ID_VENDOR_ID}=="04a9", ENV{ID_MODEL_ID}=="190f", RUN+="${pkgs.systemd}/bin/systemctl start paperless-scan.service"
      ACTION=="bind", ENV{DEVTYPE}=="usb_device", ENV{libsane_matched}=="yes", RUN+="${pkgs.systemd}/bin/systemctl start paperless-scan.service"
    '';

    # 4. Der eigenständige Scan-Service
    systemd.services.paperless-scan = lib.mkIf cfgPaperless.enable {
      description = "Universal One-Touch Scanner Action";
      serviceConfig = {
        Type = "oneshot";
        User = "paperless";
        Group = "scanner";
        ExecStart = pkgs.writeShellScript "paperless-scan-action" ''
          set -e
          TIMESTAMP=$(date +%Y%m%d_%H%M%S)
          OUTPUT_FILE="${cfgPaperless.consumptionDir}/scan_$TIMESTAMP.pdf"

          # Scan ausführen: 300dpi, Farbe
          ${pkgs.sane-frontends}/bin/scanimage \
            --format=pdf \
            --resolution 300 \
            --mode Color \
            > "$OUTPUT_FILE"
            
          echo "Scan abgeschlossen und an Paperless übergeben: $OUTPUT_FILE"
        '';
      };
    };
  };
}
