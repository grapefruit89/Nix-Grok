# ---
# meta:
#   layer: 3
#   role: module
#   purpose: SRE webhook/ntfy alerts for VPN and backup failures
#   docs:
#     - docs/guides/GUIDE-nftables-hardening.md
#   tags:
#     - alerting
#     - sre
# ---
{ config, lib, pkgs, ... }:

let
  cfg = config.my.alerting;
  hasNotify = cfg.webhookUrl != "" || cfg.ntfyTopic != "";

  notifyScript = pkgs.writeShellScript "alerting-notify" ''
    set -euo pipefail
    unit="''${FAILED_UNIT:-''${1:-unknown}}"
    msg="q958: ''${unit} failed"
    if [ -n "${cfg.ntfyTopic}" ]; then
      ${pkgs.curl}/bin/curl -fsS -m 10 \
        -H "Title: q958 alert" \
        -d "$msg" \
        "${cfg.ntfyServer}/${cfg.ntfyTopic}" || true
    fi
    if [ -n "${cfg.webhookUrl}" ]; then
      ${pkgs.curl}/bin/curl -fsS -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"$msg\"}" \
        "${cfg.webhookUrl}" || true
    fi
  '';

in
{
  options.my.alerting = {
    enable = lib.mkEnableOption "SRE webhook/ntfy alerts for VPN and backup failures";

    webhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Matrix/Slack/generic webhook URL (JSON {\"text\":…}).";
    };

    ntfyTopic = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ntfy topic — leer = ntfy deaktiviert.";
    };

    ntfyServer = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = "ntfy server base URL.";
    };
  };

  config = lib.mkIf (cfg.enable && hasNotify) {
    systemd.services.alerting-onfailure = {
      description = "Fire webhook/ntfy after triggering unit failure";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${notifyScript}";
      };
    };

    systemd.services.usenet.serviceConfig.OnFailure = lib.mkIf (
      config.my.services.vpn-confinement.enable or false
    ) (lib.mkDefault [ "alerting-onfailure.service" ]);

    systemd.services.restic-backups-tier-a-sovereign.serviceConfig.OnFailure = lib.mkIf (
      config.my.services.restic-backup.enable or false
    ) (lib.mkDefault [ "alerting-onfailure.service" ]);

    systemd.services.boot-watchdog.serviceConfig.OnFailure = lib.mkIf (
      config.my.boot-watchdog.enable or false
    ) (lib.mkDefault [ "alerting-onfailure.service" ]);
  };
}