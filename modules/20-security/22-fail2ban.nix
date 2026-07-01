# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Fail2ban Intrusion Prevention + Auditd Prozess-Monitoring
#   docs:
#     - docs/SECURITY.md
#   services:
#     - fail2ban
#   tags:
#     - security
#     - fail2ban
#     - auditd
# ---
{
  config,
  lib,
  ...
}:
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security = {
    fail2ban = {
      enable = lib.mkEnableOption "Fail2ban intrusion prevention system";
      bantime = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Default ban duration.";
      };
      findtime = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = "Time window for counting failures.";
      };
      maxretry = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Number of failures before ban.";
      };
      banaction = lib.mkOption {
        type = lib.types.enum [
          "nftables-multiport"
          "nftables-allports"
          "iptables-multiport"
        ];
        default = "nftables-multiport";
        description = "Default ban action.";
      };
      banIncrementEnable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable progressive ban time increase.";
      };
      banIncrementMultipliers = lib.mkOption {
        type = lib.types.str;
        default = "1 2 4 8 16 32 64";
        description = "Multipliers for progressive bans.";
      };
      banIncrementMaxtime = lib.mkOption {
        type = lib.types.str;
        default = "168h";
        description = "Maximum ban time (1 week).";
      };

      sshJail = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SSH jail.";
        };
        mode = lib.mkOption {
          type = lib.types.enum [
            "normal"
            "aggressive"
          ];
          default = "aggressive";
          description = "SSH jail mode.";
        };
      };

      webJails = {
        caddy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Caddy 401/403 jail.";
          };
          maxretry = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Max retries for Caddy jail.";
          };
        };
      };

      appJails = {
        vaultwarden = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Vaultwarden jail.";
          };
        };
        paperless = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Paperless jail.";
          };
        };
      };

      recidive = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable recidive jail for repeat offenders.";
        };
        bantime = lib.mkOption {
          type = lib.types.str;
          default = "168h";
          description = "Ban time for recidive (1 week).";
        };
        findtime = lib.mkOption {
          type = lib.types.str;
          default = "86400s";
          description = "Find time for recidive (1 day).";
        };
        maxretry = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Number of bans before recidive triggers.";
        };
      };
    };

    auditd = {
      enable = lib.mkEnableOption "Linux Audit daemon: execve-Syscalls loggen (Frühwarnung bei Kompromittierung)";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── FAIL2BAN INTRUSION PREVENTION ─────────────────────────────────────────
    (
      let
        cfg = config.my.security.fail2ban;
      in
      lib.mkIf cfg.enable {
        services.fail2ban = {
          enable = true;
          banaction =
            if config.my.security.firewall.enable then lib.mkForce "nftables-f2b-set" else cfg.banaction;
          inherit (cfg) bantime;
          inherit (cfg) maxretry;
          bantime-increment = {
            enable = cfg.banIncrementEnable;
            multipliers = cfg.banIncrementMultipliers;
            maxtime = cfg.banIncrementMaxtime;
          };
          jails = {
            sshd = lib.mkIf cfg.sshJail.enable {
              settings = {
                enabled = true;
                mode = cfg.sshJail.mode;
                filter = "sshd[mode=${cfg.sshJail.mode}]";
                inherit (cfg) findtime;
                inherit (cfg) maxretry;
              };
            };

            caddy-http-auth = lib.mkIf cfg.webJails.caddy.enable {
              settings = {
                enabled = true;
                filter = "caddy-json";
                action = cfg.banaction;
                maxretry = cfg.webJails.caddy.maxretry;
                inherit (cfg) findtime;
                backend = "systemd";
              };
            };

            vaultwarden = lib.mkIf cfg.appJails.vaultwarden.enable {
              settings = {
                enabled = true;
                inherit (cfg) findtime;
                inherit (cfg) maxretry;
              };
            };

            paperless = lib.mkIf cfg.appJails.paperless.enable {
              settings = {
                enabled = true;
                inherit (cfg) findtime;
                inherit (cfg) maxretry;
              };
            };

            recidive = lib.mkIf cfg.recidive.enable {
              settings = {
                enabled = true;
                logpath = "/var/log/fail2ban.log";
                inherit (cfg.recidive) bantime findtime maxretry;
              };
            };
          };
        };

        environment.etc."fail2ban/filter.d/caddy-json.conf".text = ''
          [Definition]
          failregex = ^.*"remote_ip":"<ADDR>".*"status":(401|403).*$
          journalmatch = _SYSTEMD_UNIT=caddy.service
        '';

        environment.etc."fail2ban/action.d/nftables-f2b-set.conf".text =
          lib.mkIf config.my.security.firewall.enable ''
            [Definition]
            type = firewall
            actionstart = nft add set inet filter f2b_blocked_ipv4 { type ipv4_addr \; flags timeout \; timeout 1h \; } 2>/dev/null || true
            actionstop =
            actioncheck = nft list set inet filter f2b_blocked_ipv4 >/dev/null 2>&1
            actionban = nft add element inet filter f2b_blocked_ipv4 { <ip> }
            actionunban = nft delete element inet filter f2b_blocked_ipv4 { <ip> }
          '';
      }
    )

    # ── AUDITD PROZESS-MONITORING ─────────────────────────────────────────────
    (lib.mkIf config.my.security.auditd.enable {
      security.auditd.enable = true;
      security.audit.enable = true;
      security.audit.rules = [
        # execve-Syscalls loggen — alle Prozessstarts. Ergibt Einträge im Journal (auditd).
        # Frühwarnsystem bei Kompromittierung. Performance-Overhead minimal bei Homelab-Last.
        "-a always,exit -F arch=b64 -S execve -k process_exec"
        "-a always,exit -F arch=b32 -S execve -k process_exec"
      ];
    })
  ];
}
