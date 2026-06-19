{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.recyclarr;
  dataDir = "/data/state/recyclarr";
in
{
  options.my.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr (TRaSH-Guides sync)";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d "" 0755 root root -"
      "d "/config" 0755 root root -"
    ];

    systemd.services.recyclarr-sync = {
      description = "Recyclarr TRaSH-Guides Sync";
      after = [ "network-online.target" "sonarr.service" "radarr.service" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.recyclarr ];
      script = ''
        export RECYCLARR_APP_DATA=""
        if [ ! -f "/recyclarr.yml" ]; then
          recyclarr config create
        fi
        recyclarr sync
      '';
      serviceConfig = {
        OOMScoreAdjust = 500;
        Type = "oneshot";
        User = "root";
        Group = "root";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ dataDir ];
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Daily Recyclarr Sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
