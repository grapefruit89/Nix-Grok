# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures game server environments, specifically the AMP (Application
# Management Panel) sandbox and system service.
# Key decisions -> ADR-80-gaming.md

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.amp;
  domain = config.my.configs.identity.domain;

  # FHS Sandbox Environment for running unpatched game servers inside AMP
  amp-fhs = pkgs.buildFHSEnv {
    name = "amp-fhs";
    targetPkgs =
      pkgs: with pkgs; [
        dotnet-sdk_8
        glibc
        glibc.dev
        stdenv.cc.cc.lib # libstdc++
        openssl
        curl
        sqlite
        screen
        bash
        coreutils
        procps
        findutils
        steamcmd
        icu
        zlib
        krb5
      ];
    multiPkgs =
      pkgs: with pkgs; [
        pkgsi686Linux.glibc
      ];
    runScript = "bash";
  };

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.amp = {
    enable = lib.mkEnableOption "AMP Game Server Manager";
    port = lib.mkOption {
      type = lib.types.port;
      default = config.my.ports.amp;
      description = "AMP Web UI port.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/amp";
      description = "AMP data directory.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # ── 1. SYSTEM PACKAGES ───────────────────────────────────────────────────
    environment.systemPackages = [ amp-fhs ];

    # ── 2. SYSTEMD SERVICE ────────────────────────────────────────────────────
    systemd.services.amp = {
      description = "AMP Game Server Manager (Native FHS)";
      after = [
        "network.target"
        "local-fs.target"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${amp-fhs}/bin/amp-fhs -c 'ampinstmgr startall'";
        User = "amp";
        Group = "amp";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = "10s";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Paths
        ReadWritePaths = [ cfg.dataDir ];
        # AMP needs to spawn game servers (forking, networking)
        PrivateNetwork = false;
        PrivateUsers = false;
        PrivateDevices = false;
      };
    };

    # ── 3. SYSTEM USER ────────────────────────────────────────────────────────
    users.users.amp = {
      isSystemUser = true;
      group = "amp";
      home = cfg.dataDir;
      createHome = true;
      shell = "${amp-fhs}/bin/amp-fhs"; # Allow entering FHS sandbox
    };
    users.groups.amp = { };

    # ── 4. DIRECTORY CREATION ─────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 amp amp -"
    ];

    # ── 5. CADDY INGRESS ──────────────────────────────────────────────────────
    services.caddy.virtualHosts."amp.${domain}" = {
      extraConfig = ''
        import security_headers
        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';
    };
  };
}
