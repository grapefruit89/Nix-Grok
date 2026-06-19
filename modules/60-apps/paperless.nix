/*
  ---
  id: paperless
  upstream_repo: "paperless-ngx/paperless-ngx"
  ---
*/

{ config, lib, pkgs, ... }:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgPaperless = config.my.services.paperless;
  domain = config.my.configs.identity.domain;

in
{
  config = lib.mkIf cfgPaperless.enable {
    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      inherit (cfgPaperless) port;
      inherit (cfgPaperless) dataDir;
      inherit (cfgPaperless) consumptionDir;
      settings = {
        PAPERLESS_URL = "https://paperless.${domain}";
        PAPERLESS_ALLOWED_HOSTS = "localhost,127.0.0.1,paperless.${domain}";
        PAPERLESS_TIME_ZONE = "Europe/Berlin";
        PAPERLESS_OCR_LANGUAGE = "deu";
        PAPERLESS_OCR_MODE = "skip";
        PAPERLESS_OCR_DESKEW = "true";
        PAPERLESS_OCR_CLEAN = "clean";
        PAPERLESS_OCR_OUTPUT_TYPE = "pdfa";
        PAPERLESS_REDIS = "unix:///run/redis-valkey/valkey.sock";
        PAPERLESS_TASK_WORKERS = "2";
        PAPERLESS_THREADS_PER_WORKER = "2";
      };
    };

    users.users.paperless.extraGroups = [
      "redis"
      "scanner"
      "lp"
    ];

    systemd.services.paperless-web.serviceConfig = {
      OOMScoreAdjust = -500;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ReadWritePaths = [
        cfgPaperless.dataDir
        cfgPaperless.consumptionDir
      ];
      CapabilityBoundingSet = "";
      RestrictNamespaces = true;
      ProtectClock = true;
      ProtectHostname = true;
      LockPersonality = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };

    services.caddy.virtualHosts."paperless.${domain}" = {
      extraConfig = caddy.proxySso cfgPaperless.port;
    };

    # ── SANE SCANNER & ONE-TOUCH OCR ──────────────────────────────────────────
    # Deklarative SANE-Einrichtung für Canon CanoScan LiDE 220
    hardware.sane = {
      enable = true;
      extraBackends = [ pkgs.sane-backends ];
    };

    # Udev Rule: Wenn der Scanner-Knopf gedrückt wird, triggern wir ein Script, das den SANE-Scan
    # startet und das Ergebnis direkt als PDF in den Paperless consume-Ordner wirft.
    services.udev.extraRules = ''
      # Canon CanoScan LiDE 220 Scanner-Knopf-Event
      ACTION=="bind", ENV{DEVTYPE}=="usb_device", ENV{ID_VENDOR_ID}=="04a9", ENV{ID_MODEL_ID}=="190f", RUN+="${pkgs.systemd}/bin/systemctl start paperless-scan.service"
    '';

    systemd.services.paperless-scan = {
      description = "Paperless One-Touch Scanner Action";
      # Der Service wird per udev getriggert, wenn der Scanner eingesteckt / gedrückt wird.
      # (In einer finalen Ausbaustufe kann hier der scanbd-Daemon für exakte Button-Auswertung laufen)
      serviceConfig = {
        Type = "oneshot";
        User = "paperless";
        Group = "scanner";
        ExecStart = pkgs.writeShellScript "paperless-scan-action" ''
          set -e
          TIMESTAMP=$(date +%Y%m%d_%H%M%S)
          OUTPUT_FILE="${cfgPaperless.consumptionDir}/scan_$TIMESTAMP.pdf"

          # Scan ausführen: 300dpi, Farbe (optimal für Paperless OCR)
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
