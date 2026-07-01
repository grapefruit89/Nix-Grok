# ---
# meta:
#   layer: 3
#   role: module
#   purpose: SSH-Härtung (Zero-Trust Production + Dev), Dropbear-Rescue
#   docs:
#     - docs/SECURITY.md
#   services:
#     - sshd
#   tags:
#     - security
#     - ssh
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgSsh = config.my.security.ssh-zerotrust;
  user = config.my.configs.identity.user;
  sshPort = config.my.ports.ssh;
  hasAuthorizedKeys = (config.users.users.${user}.openssh.authorizedKeys.keys or [ ]) != [ ];
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security = {
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
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── DEVELOPMENT SSHD ──────────────────────────────────────────────────────
    (lib.mkIf (config.my.mode == "development") {
      services.openssh = {
        enable = true;
        ports = lib.mkForce [ 22 ];
        settings = {
          # Root nur ueber die physische TTY-Konsole (autologin), nie ueber SSH.
          PermitRootLogin = lib.mkForce "no";
          PasswordAuthentication = lib.mkForce false;
          KbdInteractiveAuthentication = lib.mkForce false;
        };
      };

      # Copy admin public keys to root user for easy passwordless access
      users.users.root.openssh.authorizedKeys.keys =
        config.users.users.${user}.openssh.authorizedKeys.keys or [ ];
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
          KexAlgorithms = [
            "curve25519-sha256"
            "curve25519-sha256@libssh.org"
          ];
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
          ];
          Macs = [
            "hmac-sha2-512-etm@openssh.com"
            "hmac-sha2-256-etm@openssh.com"
          ];
        };
        extraConfig = lib.mkForce ''
          Match Address 127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10
            PermitTTY yes
          Match All
            PermitTTY no
        '';
      };

      systemd.services.sshd.serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
        OOMScoreAdjust = lib.mkForce (-1000); # SSH-Daemon darf unter OOM nicht getötet werden
        ProtectSystem = "full";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };

      assertions = [
        {
          assertion = hasAuthorizedKeys;
          message = "Sicherheits-Blockade: deployment verboten ohne SSH-Authorized-Keys in users.nix";
        }
      ];
    })

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
