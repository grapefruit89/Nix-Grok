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
  cidrs = import ../../lib/network-cidrs.nix { inherit lib config; };
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
        default = config.my.ports.dropbear;
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
          Match Address ${cidrs.sshMatchAddresses}
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
        # authorized_keys via Symlinks aus NixOS-managed /etc/ssh/authorized_keys.d/
        # — kein ExecStartPre, kein Runtime-Copy, kein chmod
        systemd.tmpfiles.rules = [
          "d /home/${user}/.ssh 0700 ${user} users -"
          "L+ /home/${user}/.ssh/authorized_keys - - - - /etc/ssh/authorized_keys.d/${user}"
          "d /root/.ssh 0700 root root -"
          "L+ /root/.ssh/authorized_keys - - - - /etc/ssh/authorized_keys.d/root"
        ];

        systemd.services.dropbear-rescue = {
          description = "Dropbear emergency rescue SSH server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          serviceConfig = {
            Type = "simple";
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
