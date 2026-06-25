# ---
# meta:
#   id: NIXH-05-MOD-004
#   layer: 3
#   role: module
#   purpose: Runtime Security Watchdog — nftables/sshd/lockdown live prüfen
#   tags:
#     - security
#     - runtime
# ---
{ config, lib, pkgs, ... }:

let
  cfg = config.my.security.runtime-guard;
in
{
  options.my.security.runtime-guard = {
    enable = lib.mkEnableOption "Runtime security watchdog (Build ≠ Runtime)";
    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "systemd OnCalendar für security-watchdog.";
    };
    requireNftables = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    requireAdminAlias = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "127.0.0.2 Admin-Hangar — q958 nutzt tailscale_admin statt lo:2.";
    };
    requireKernelLockdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Prüft /sys/kernel/security/lockdown — nur mit hardened.lockKernelModules sinnvoll.";
    };
    requireFail2ban = lib.mkOption {
      type = lib.types.bool;
      default = config.my.security.fail2ban.enable or false;
    };
    requireCrowdsec = lib.mkOption {
      type = lib.types.bool;
      default = config.my.security.crowdsec.enable or false;
    };
  };

  config = lib.mkIf cfg.enable {
    my.security.runtime-guard.requireKernelLockdown = lib.mkDefault (
      config.my.security.hardened.lockKernelModules or false
    );

    systemd.services.security-watchdog = {
      description = "Runtime security check (nftables, sshd, lockdown)";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script =
        let
          nft = "${pkgs.nftables}/bin/nft";
          grep = "${pkgs.gnugrep}/bin/grep";
          sshd = "${pkgs.openssh}/bin/sshd";
          ip = "${pkgs.iproute2}/bin/ip";
          systemctl = "${pkgs.systemd}/bin/systemctl";
        in
        ''
          set -euo pipefail
          ${lib.optionalString cfg.requireNftables ''
            if ! ${nft} list tables 2>/dev/null | ${grep} -q "inet filter"; then
              echo "[RUNTIME-GUARD] nftables inet filter fehlt"
              exit 1
            fi
          ''}
          ${lib.optionalString (config.my.mode == "production") ''
            if ${sshd} -T 2>/dev/null | ${grep} -q "permitrootlogin yes"; then
              echo "[RUNTIME-GUARD] sshd erlaubt Root-Login"
              exit 1
            fi
          ''}
          ${lib.optionalString cfg.requireKernelLockdown ''
            if [ -r /sys/kernel/security/lockdown ]; then
              if ${grep} -q '\[none\]' /sys/kernel/security/lockdown; then
                echo "[RUNTIME-GUARD] kernel lockdown ist [none]"
                exit 1
              fi
            fi
          ''}
          ${lib.optionalString cfg.requireFail2ban ''
            if ! ${systemctl} is-active --quiet fail2ban.service; then
              echo "[RUNTIME-GUARD] fail2ban.service nicht aktiv"
              exit 1
            fi
          ''}
          ${lib.optionalString cfg.requireCrowdsec ''
            if ! ${systemctl} is-active --quiet crowdsec.service; then
              echo "[RUNTIME-GUARD] crowdsec.service nicht aktiv"
              exit 1
            fi
          ''}
          ${lib.optionalString cfg.requireAdminAlias ''
            if ! ${ip} addr show lo | ${grep} -q "127.0.0.2"; then
              echo "[RUNTIME-GUARD] Admin-Alias 127.0.0.2 fehlt"
              exit 1
            fi
          ''}
        '';
    };

    systemd.timers.security-watchdog = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };
}