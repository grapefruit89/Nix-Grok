{ config, lib, pkgs, ... }:

let
  cfgSonarr = config.my.services.sonarr;
  cfgRadarr = config.my.services.radarr;
  cfgProwlarr = config.my.services.prowlarr;
  cfgSabnzbd = config.my.services.sabnzbd;
  cfgJellyfin = config.my.services.jellyfin;

  anyEnabled = cfgSonarr.enable || cfgRadarr.enable || cfgProwlarr.enable || cfgSabnzbd.enable || cfgJellyfin.enable;

in
{
  config = lib.mkIf anyEnabled {
    systemd.services.media-stack-config-sync = {
      description = "Declarative Media Stack Locale and Application Sync Orchestrator";
      after = [ "prowlarr.service" "sonarr.service" "radarr.service" "sabnzbd.service" "jellyfin.service" ];
      wants = [ "prowlarr.service" "sonarr.service" "radarr.service" "sabnzbd.service" "jellyfin.service" ];
      
      path = with pkgs; [ curl jq gnugrep coreutils python3 systemd ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      environment = {
        TARGET_LANG = config.my.configs.locale.language;
        TARGET_LOCALE = config.my.configs.locale.default;
      };

      script = builtins.readFile ./sync-script.sh;
        systemd.timers.media-stack-config-sync = {
      description = "Delay Media Stack Config Sync after Boot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1d";
      };
      };
}




