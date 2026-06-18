{ config, lib, pkgs, ... }:

{
  options.my.security.runtime-guard = {
    enable = lib.mkEnableOption "Runtime Security Monitoring (Watchdog)";
    interval = lib.mkOption { 
      type = lib.types.str; 
      default = "hourly"; 
      description = "Wie oft der Watchdog prüfen soll (systemd timer Format).";
    };
  };

  config = lib.mkIf config.my.security.runtime-guard.enable {
    
    # ==========================================================================
    # RUNTIME SECURITY WATCHDOG
    # ==========================================================================
    # Dieser Service prüft den tatsächlichen, lebenden Systemzustand zur Laufzeit.
    # Selbst wenn die Nix-Konfiguration korrekt ist, könnte ein Dienst abstürzen
    # oder manuell manipuliert werden. Der Watchdog schlägt Alarm, wenn kritische
    # Kernfunktionen nicht den Erwartungen entsprechen.

    systemd.services.security-watchdog = {
      description = "Runtime Security & Compliance Check";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = '
        set -euo pipefail
        
        echo "=== RUNTIME SECURITY WATCHDOG gestartet ==="

        # 1. Check Firewall (nftables active)
        # Die nftables filter table MUSS existieren, sonst ist der Server ungeschützt!
        if ! ${pkgs.nftables}/bin/nft list tables | ${pkgs.gnugrep}/bin/grep -q -- "inet filter"; then
          echo "CRITICAL: nftables 'inet filter' table FEHLT! Firewall ist offline!"
          exit 1
        fi

        # 2. Check Kernel Lockdown Status (falls Kernel-Modus aktiviert ist)
        if [ -d /sys/kernel/security/lockdown ]; then
          LOCKDOWN=$(${pkgs.coreutils}/bin/cat -- /sys/kernel/security/lockdown | ${pkgs.gnugrep}/bin/grep -o '\[.*\]' | ${pkgs.gnused}/bin/sed 's/\[//;s/\]//')
          if [ "$LOCKDOWN" != "confidentiality" ] && [ "$LOCKDOWN" != "integrity" ]; then
            echo "WARN: Kernel Lockdown ist inaktiv (Status: $LOCKDOWN)"
          fi
        fi

        # 3. Check SSH Root Login (Verhindern von direkten Root-Logins)
        if ${pkgs.openssh}/bin/sshd -T | ${pkgs.gnugrep}/bin/grep -q -- "permitrootlogin yes"; then
          echo "CRITICAL: sshd erlaubt Root-Login in der aktiven Konfiguration!"
          exit 1
        fi

        echo "=== RUNTIME SECURITY WATCHDOG erfolgreich ==="
      ';
    };

    systemd.timers.security-watchdog = {
      description = "Timer für Runtime Security Check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = config.my.security.runtime-guard.interval;
        Persistent = true;
      };
    };

    # ==========================================================================
    # FLUGSCHREIBER WATCHDOG (Auto-Rollback)
    # ==========================================================================
    systemd.services.boot-watchdog = {
      description = "Boot Stabilitäts-Watchdog (Auto-Rollback)";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -euo pipefail
        
        echo "=== BOOT WATCHDOG Check ==="
        
        if systemctl is-failed --quiet caddy.service; then
           echo "CRITICAL: Caddy is in failed state!"
           # Rollback nur beim ersten Boot-Check (Uptime < 15 Min)
           UPTIME_SEC=$(${pkgs.coreutils}/bin/cat /proc/uptime | ${pkgs.gawk}/bin/awk '{print $1}' | ${pkgs.coreutils}/bin/cut -d. -f1)
           if [ "$UPTIME_SEC" -lt 900 ]; then
             echo "Triggering Auto-Rollback!"
             /run/current-system/bin/switch-to-configuration boot
             reboot
           else
             echo "Uptime > 15m. Logge Fehler ohne Reboot, um Wartungsarbeiten nicht zu stören."
           fi
           exit 1
        fi
        
        echo "System ist stabil."
      '';
    };

    systemd.timers.boot-watchdog-2m = {
      description = "Boot Watchdog (2 Minuten)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        Unit = "boot-watchdog.service";
      };
    };

    systemd.timers.boot-watchdog-30m = {
      description = "Boot Watchdog (30 Minuten)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30min";
        Unit = "boot-watchdog.service";
      };
    };

    systemd.timers.boot-watchdog-60m = {
      description = "Boot Watchdog (60 Minuten)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "60min";
        Unit = "boot-watchdog.service";
      };
    };

  };
}

