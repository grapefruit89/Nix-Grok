
# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures the hardware-bound multi-factor Sovereign Unlock initrd cascade
# (TPM2.0 / Tang / FIDO2 / SSH Port 2222) and hardened Zero-Trust production SSH.
# Key decisions -> ADR-20-security.md

{ config, lib, pkgs, ... }:

let
  cfgUnlock = config.my.security.sovereign-unlock;
  cfgSsh = config.my.security.ssh-zerotrust;

  user = config.my.configs.identity.user;
  sshPort = config.my.ports.ssh;
  hasAuthorizedKeys = (config.users.users.${user}.openssh.authorizedKeys.keys or [ ]) != [ ];

  # Emergency QR-Code Script
  qrFallbackScript = pkgs.writeShellScript "nms-qr-fallback" ''
    set -euo pipefail
    sleep 30
    if [ -e /dev/mapper/sovereign_vault ] 2>/dev/null; then
      exit 0
    fi
    IP=$(ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    SSH_CMD="ssh -p ${toString cfgUnlock.sshPort} root@''${IP:-<server-ip>}"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     NMS v4.2 - SOVEREIGN IDENTITY FALLBACK              ║"
    echo "║                                                          ║"
    echo "║  Automatischer Unlock fehlgeschlagen.                   ║"
    echo "║  Bitte einen der folgenden Wege nutzen:                 ║"
    echo "║                                                          ║"
    echo "║  1. YubiKey einstecken und berühren                     ║"
    echo "║  2. Per SSH entsperren (QR-Code scannen):               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    ${pkgs.qrencode}/bin/qrencode -t ANSIUTF8 "$SSH_CMD"
    echo ""
    echo "  SSH: $SSH_CMD"
    echo "  Dann: systemd-tty-ask-password-agent"
  '';

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security = {
    sovereign-unlock = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.my.mode == "production";
        description = "Sovereign Unlock LUKS cascade (TPM2/Tang/FIDO2/initrd-SSH)";
      };
      luksDevice = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "LUKS device path (set in machines/<host>/profile.nix).";
      };
      tangServer = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      sshPort = lib.mkOption {
        type = lib.types.int;
        default = 2222;
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      hostKey = lib.mkOption {
        type = lib.types.str;
        default = "/persist/etc/ssh/ssh_host_ed25519_key";
      };
    };

    ssh-zerotrust.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.my.mode == "production";
      description = "Hardened Zero-Trust Production SSH settings";
    };

    dropbear-rescue = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Dropbear rescue SSH daemon on the main system (stage 2) on a custom port.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 2222;
        description = "Port for the Dropbear rescue daemon.";
      };
    };

    fail2ban = {
      enable = lib.mkEnableOption "Fail2ban intrusion prevention system";
      bantime = lib.mkOption { type = lib.types.str; default = "1h"; description = "Default ban duration."; };
      findtime = lib.mkOption { type = lib.types.str; default = "10m"; description = "Time window for counting failures."; };
      maxretry = lib.mkOption { type = lib.types.int; default = 5; description = "Number of failures before ban."; };
      banaction = lib.mkOption {
        type = lib.types.enum [ "nftables-multiport" "nftables-allports" "iptables-multiport" ];
        default = "nftables-multiport";
        description = "Default ban action.";
      };
      banIncrementEnable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable progressive ban time increase."; };
      banIncrementMultipliers = lib.mkOption { type = lib.types.str; default = "1 2 4 8 16 32 64"; description = "Multipliers for progressive bans."; };
      banIncrementMaxtime = lib.mkOption { type = lib.types.str; default = "168h"; description = "Maximum ban time (1 week)."; };

      sshJail = {
        enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable SSH jail."; };
        mode = lib.mkOption { type = lib.types.enum [ "normal" "aggressive" ]; default = "aggressive"; description = "SSH jail mode."; };
      };

      webJails = {
        caddy = {
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable Caddy 401/403 jail."; };
          maxretry = lib.mkOption { type = lib.types.int; default = 10; description = "Max retries for Caddy jail."; };
        };
      };

      appJails = {
        vaultwarden = { enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Vaultwarden jail."; }; };
        paperless = { enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable Paperless jail."; }; };
      };

      recidive = {
        enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable recidive jail for repeat offenders."; };
        bantime = lib.mkOption { type = lib.types.str; default = "168h"; description = "Ban time for recidive (1 week)."; };
        findtime = lib.mkOption { type = lib.types.str; default = "86400s"; description = "Find time for recidive (1 day)."; };
        maxretry = lib.mkOption { type = lib.types.int; default = 3; description = "Number of bans before recidive triggers."; };
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── SOVEREIGN UNLOCK CASCADE ──────────────────────────────────────────────
    (lib.mkIf cfgUnlock.enable {
      boot = {
        initrd = {
          systemd.enable = true;

          luks.devices."sovereign_vault" = {
            device = cfgUnlock.luksDevice;
            crypttabExtraOpts = [
              "tpm2-device=auto"
              "tpm2-pcrs=0+1+7"
              "fido2-device=auto"
              "fido2-with-client-pin=false"
            ];
          };

          clevis = lib.mkIf (cfgUnlock.tangServer != "") {
            enable = true;
            devices."sovereign_vault".secretFile = "/run/nms-network-trusted";
          };

          network = {
            enable = true;
            ssh = lib.mkIf (cfgUnlock.authorizedKeys != [ ]) {
              enable = true;
              port = cfgUnlock.sshPort;
              inherit (cfgUnlock) authorizedKeys;
              hostKeys = [ cfgUnlock.hostKey ];
              shell = "${pkgs.writeShellScript "initrd-unlock-shell" ''
                echo "NMS v4.2 - Remote initrd Unlock Shell"
                echo "Unlock command: systemd-tty-ask-password-agent"
                exec ${pkgs.bashInteractive}/bin/bash
              ''}";
            };
          };

          systemd.services.nms-qr-fallback = {
            description = "NMS Emergency TTY QR-Code Fallback";
            wantedBy = [ "initrd.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = qrFallbackScript;
              RemainAfterExit = false;
            };
          };

          availableKernelModules = [
            "xhci_pci"
            "ehci_pci"
            "xhci_hcd"
            "usb_storage"
            "uas"
            "r8169"
            "e1000e"
            "igb"
            "ixgbe"
            "tg3"
            "atlantic"
            "r8152"
            "ax88179_178a"
            "cdc_ether"
            "tpm_tis"
            "tpm_crb"
            "tpm_tis_core"
            "dm_crypt"
            "aes"
          ];
        };
      };

      assertions = [{
        assertion = cfgUnlock.authorizedKeys != [ ] || cfgUnlock.tangServer != "";
        message = "Sovereign Unlock: Entweder initrd SSH-Keys oder ein Tang-Server müssen konfiguriert sein.";
      }];
    })

    # ── DEVELOPMENT SSHD ──────────────────────────────────────────────────────
    (lib.mkIf (config.my.mode == "development") {
      services.openssh = {
        enable = true;
        ports = lib.mkForce [ 22 ];
        settings = {
          PermitRootLogin = lib.mkForce "yes";
          PasswordAuthentication = lib.mkForce true;
          KbdInteractiveAuthentication = lib.mkForce true;
        };
      };

      # Copy admin public keys to root user for easy passwordless access
      users.users.root.openssh.authorizedKeys.keys = config.users.users.${user}.openssh.authorizedKeys.keys or [ ];
    })

    # ── ZERO-TRUST HARDENED SSHD ──────────────────────────────────────────────
    (lib.mkIf (config.my.mode == "production" && cfgSsh.enable) {
      services.openssh = {
        enable = true;
        openFirewall = false;
        ports = lib.mkForce [ sshPort ];

        settings = {
          PermitRootLogin = lib.mkForce "no";
          PasswordAuthentication = lib.mkForce false; # Passwort-Auth komplett verboten
          KbdInteractiveAuthentication = lib.mkForce false;
          AuthorizedKeysFile = ".ssh/authorized_keys";

          LoginGraceTime = 20;
          MaxAuthTries = 3;
          ClientAliveInterval = 300;
          ClientAliveCountMax = 2;
          MaxSessions = 10;
          PermitEmptyPasswords = false;
          X11Forwarding = false;
          AllowAgentForwarding = false;
          AllowTcpForwarding = true; # Erlaubt Tunneling über sicheren Tailscale-Kanal

          # Post-Quantum / Hardened Krypto-Verfahren
          HostKeyAlgorithms = "ssh-ed25519,ssh-rsa";
          PubkeyAcceptedAlgorithms = "+ssh-rsa";
          KexAlgorithms = [ "curve25519-sha256" "curve25519-sha256@libssh.org" ];
          Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ];
          Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" ];
        };
        extraConfig = lib.mkForce "";
      };



      # Rate-Limiting für SSH per nftables zum Schutz vor Brute-Force
      networking.firewall.extraInputRules = lib.mkAfter ''
        tcp dport ${toString sshPort} ct state new \
          limit rate over 10/minute \
          drop comment "SSH brute-force rate limiting"
      '';

      systemd.services.sshd.serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        OOMScoreAdjust = lib.mkForce (-1000); # SSH-Daemon darf unter OOM nicht getötet werden
        ProtectSystem = "full";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };

      assertions = [{
        assertion = hasAuthorizedKeys;
        message = "Sicherheits-Blockade: deployment verboten ohne SSH-Authorized-Keys in users.nix";
      }];
    })

    # ── FAIL2BAN INTRUSION PREVENTION ─────────────────────────────────────────
    (
      let
        cfg = config.my.security.fail2ban;
      in
      lib.mkIf cfg.enable {
        systemd.tmpfiles.rules = [
          "d /data/state/fail2ban 0700 root root -"
        ];

        services.fail2ban = {
          enable = true;
          ignoreIP = [ "127.0.0.0/8" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10" "169.254.0.0/16" ];
          daemon.settings.Definition.dbfile = "/data/state/fail2ban/fail2ban.sqlite3";
          inherit (cfg) banaction;
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
                backend = "systemd";
                journalmatch = "_SYSTEMD_UNIT=sshd.service + _SYSTEMD_UNIT=sshd-session.service";
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
                filter = "vaultwarden";
                backend = "systemd";
                journalmatch = "_SYSTEMD_UNIT=vaultwarden.service";
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

        environment.etc."fail2ban/filter.d/vaultwarden.conf".text = ''
          [Definition]
          failregex = ^.*Invalid password for '.*' from <HOST>.*$
                      ^.*IP <HOST> blocked.*$
          journalmatch = _SYSTEMD_UNIT=vaultwarden.service
        '';
      }
    )

    # ── DROPBEAR STAGE-2 RESCUE DAEMON ────────────────────────────────────────
    (
      let
        cfgRescue = config.my.security.dropbear-rescue;
      in
      lib.mkIf cfgRescue.enable {
        systemd.services.dropbear-rescue = {
          description = "Dropbear emergency rescue SSH server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStartPre = pkgs.writeShellScript "dropbear-rescue-prepare" ''
              USER="${user}"
              mkdir -p "/home/$USER/.ssh" /root/.ssh
              chmod 700 "/home/$USER/.ssh" /root/.ssh

              if [ -f "/etc/ssh/authorized_keys.d/$USER" ]; then
                cp "/etc/ssh/authorized_keys.d/$USER" "/home/$USER/.ssh/authorized_keys"
                chmod 600 "/home/$USER/.ssh/authorized_keys"
                chown "$USER:users" "/home/$USER/.ssh/authorized_keys"
              fi

              if [ -f "/etc/ssh/authorized_keys.d/$USER" ]; then
                cp "/etc/ssh/authorized_keys.d/$USER" /root/.ssh/authorized_keys
                chmod 600 /root/.ssh/authorized_keys
                chown root:root /root/.ssh/authorized_keys
              fi
            '';
            ExecStart = "${pkgs.dropbear}/bin/dropbear -F -E -s -p ${toString cfgRescue.port} -r /var/lib/dropbear/dropbear_ed25519_host_key -R";
            Restart = "always";
            RestartSec = "10s";
            StateDirectory = "dropbear";
          };
        };
      }
    )
  ];
}


