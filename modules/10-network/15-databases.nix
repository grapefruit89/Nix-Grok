{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgValkey = config.my.services.valkey;
  cfgPostgres = config.my.services.postgresql;
  ramGB = config.my.configs.hardware.ramGB;
  sockets = import ../../lib/unix-sockets.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix { inherit lib; };
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    valkey.enable = lib.mkEnableOption "Valkey cache server (Redis-fork)";
    postgresql.enable = lib.mkEnableOption "PostgreSQL database server";
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── VALKEY CACHE DATABASE (Valkey package inside Redis module) ────────────
    (lib.mkIf cfgValkey.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/redis-valkey 0750 redis redis -"
      ];

      services.redis = {
        package = pkgs.valkey;
        servers.valkey = {
          enable = true;
          port = 0; # nur UDS — kein TCP
          openFirewall = false;
          unixSocket = sockets.valkey;
          unixSocketPerm = 666;
          settings = {
            maxmemory = "256mb";
            maxmemory-policy = "allkeys-lru";
            save = [
              "900 1"
              "300 10"
            ];
          };
        };
      };

      # Valkey Server Sandboxing
      systemd.services.redis-valkey.serviceConfig = {
        RuntimeDirectoryMode = lib.mkForce "0755";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        ReadWritePaths = [ "/var/lib/redis-valkey" ];
        ProtectProc = "invisible";
        ProtectKernelLogs = true;
      };
    })

    # ── POSTGRESQL DATABASE SERVER ────────────────────────────────────────────
    (lib.mkIf cfgPostgres.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/postgresql 0700 postgres postgres -"
      ];

      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;

        # Rationale: Liegt auf Fast-Tier SSD/NVMe (Ext4/Btrfs mit noatime), getrennt von mergerfs
        dataDir = "/var/lib/postgresql";

        # Unix Sockets only — enableTCPIP=false lässt nixpkgs sonst localhost:5432 offen
        enableTCPIP = false;

        # Streng lokaler Socket-Zugriff per Ident-Validation
        authentication = pkgs.lib.mkForce ''
          # TYPE  DATABASE        USER            ADDRESS                 METHOD
          local   all             all                                     ident
        '';

        settings = {
          listen_addresses = lib.mkForce "";
          shared_buffers = "${toString (lib.max 1 (lib.floor (ramGB * 0.25)))}GB";
          work_mem = "64MB";
          maintenance_work_mem = "${toString (lib.max 128 (lib.floor (ramGB * 64)))}MB";
          effective_cache_size = "${toString (lib.max 1 (lib.floor (ramGB * 0.375)))}GB";
          max_connections = 100;
        };
      };

      # PostgreSQL Systemd Sandboxing Härtung
      systemd.services.postgresql.serviceConfig = lib.mkMerge [
        (memory.postgres ramGB)
        {
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
          ReadWritePaths = [ "/var/lib/postgresql" ];
          ProtectProc = "invisible";
          ProtectKernelLogs = true;
        }
      ];
    })
  ];
}
