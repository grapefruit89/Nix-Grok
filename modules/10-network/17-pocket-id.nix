{
  config,
  lib,
  ...
}:
let
  cfgPocketId = config.my.services.pocket-id;
  domain = config.my.configs.identity.domain;
  memory = import ../../lib/memory-policy.nix { inherit lib; };
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  # 🔑 PocketID Identity Provider
  options.my.services.pocket-id = {
    enable = lib.mkEnableOption "PocketID OIDC Passkey Provider";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.pocket-id;
      description = "PocketID web interface listening port.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pocket-id";
      description = "Database state directory.";
    };
    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Optional env file (ENCRYPTION_KEY=…) — Pfad aus machines/<host>/profile.nix.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfgPocketId.enable {
    systemd.services.pocket-id = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # Pocket-ID nutzt Port 1001 (< 1024) ohne Root — Kernel-Schwelle absenken
    boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = lib.mkDefault 1000;

    services.pocket-id = {
      enable = true;
      dataDir = cfgPocketId.dataDir;
      settings = {
        PORT = toString cfgPocketId.port;
        PUBLIC_URL = "https://auth.${domain}";
        RP_ID = "auth.${domain}";
        RP_NAME = "PocketID";
        SESSION_DURATION = "24h";
        ATTESTATION = "direct";
        USER_VERIFICATION = "preferred";
        PUBLIC_REGISTRATION = "false";
        TRUST_PROXY = true;
      };
    };

    systemd.services.pocket-id.serviceConfig = lib.mkMerge [
      (memory.pocketId { })
      {
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ReadWritePaths = [ cfgPocketId.dataDir ];
      }
      (lib.mkIf (cfgPocketId.secretsFile != "") {
        EnvironmentFile = lib.mkAfter [ "-${cfgPocketId.secretsFile}" ];
      })
    ];

    my.impermanence.extraPaths = [
      cfgPocketId.dataDir
    ];
  };
}
