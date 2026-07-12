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
  sshdRestart = {
    Restart = lib.mkForce "always";
    RestartSec = lib.mkForce "5s";
    OOMScoreAdjust = lib.mkForce (-1000);
  };
in
{
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
        description = "Enable Dropbear rescue SSH daemon on custom port";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.dropbear;
        description = "Port for the Dropbear rescue daemon.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.my.mode == "development") {
      services.openssh = {
        enable = true;
        ports = lib.mkForce [ 22 ];
        settings = {
          PermitRootLogin = lib.mkForce "no";
          PasswordAuthentication = lib.mkForce false;
          KbdInteractiveAuthentication = lib.mkForce false;
          HostKeyAlgorithms = "ssh-ed25519";
          PubkeyAcceptedAlgorithms = "ssh-ed25519";
        };
      };

      systemd.services.sshd.serviceConfig = sshdRestart;
    })

    (lib.mkIf (config.my.mode == "production" && cfgSsh.enable) {
      services.openssh = {
        enable = true;
        openFirewall = false;
        ports = lib.mkForce [ sshPort ];

        settings = {
          PermitRootLogin = lib.mkForce "no";
          PasswordAuthentication = lib.mkForce false;
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
          AllowTcpForwarding = true;

          HostKeyAlgorithms = "ssh-ed25519";
          PubkeyAcceptedAlgorithms = "ssh-ed25519";
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

      systemd.services.sshd.serviceConfig = sshdRestart // {
        ProtectSystem = "full";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    })

    (
      let
        cfgRescue = config.my.security.dropbear-rescue;
      in
      lib.mkIf cfgRescue.enable {
        systemd.tmpfiles.rules = [
          "d /home/${user}/.ssh 0700 ${user} users -"
          "L+ /home/${user}/.ssh/authorized_keys - - - - /etc/ssh/authorized_keys.d/${user}"
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
