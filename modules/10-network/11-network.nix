# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Technitium DNS, Valkey, PostgreSQL, Netbird VPN, Pocket-ID, Privado
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
#     - docs/adr/002-ipv6-homelab-v4-only.md
#     - docs/adr/014-caddy-security-headers-trusted-proxies.md
#     - docs/adr/018-caddy-dual-log-dsgvo.md
#   lib:
#     - lib/memory-policy.nix
#     - lib/critical-systemd.nix
#   services:
#     - technitium-dns-server
#     - postgresql
#     - redis-valkey
#     - netbird
#     - pocket-id
#   tags:
#     - dns
#     - network
#     - database
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgTechnitium = config.my.services.technitium-dns-server;
  cfgValkey = config.my.services.valkey;
  cfgPostgres = config.my.services.postgresql;
  cfgNetbird = config.my.services.netbird;
  ramGB = config.my.configs.hardware.ramGB;
  sockets = import ../../lib/unix-sockets.nix { inherit lib; };

  memory = import ../../lib/memory-policy.nix { inherit lib; };
  domain = config.my.configs.identity.domain;
  caddySnippets = import ../../lib/caddy-snippets.nix {
    inherit lib;
    pocketIdPort =
      if config.my.services.pocket-id.enable or false then config.my.ports.pocket-id else null;
    lanCidr = "192.168.0.0/16";
  };
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    technitium-dns-server.enable = lib.mkEnableOption "Technitium DNS Server";
    valkey.enable = lib.mkEnableOption "Valkey cache server (Redis-fork)";
    postgresql.enable = lib.mkEnableOption "PostgreSQL database server";

    # 🌐 Netbird Self-Hosted VPN
    netbird = {
      enable = lib.mkEnableOption "Netbird Self-Hosted VPN (Management + Signal + Client)";
      domain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Domain for Netbird management server (e.g. netbird.example.com).";
      };
      setupKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/secrets/netbird_setup_key";
        description = "Path to file containing the Netbird setup key for auto-login.";
      };
    };

    # 🛡️ Privado VPN WireGuard Client
    privado-vpn = {
      enable = lib.mkEnableOption "Privado VPN WireGuard Client Tunnel";
      ipAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.0.0.2/32";
        description = "Privado VPN interface IP address.";
      };
      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "10.255.255.255" ];
        description = "DNS servers to bind to the VPN interface.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Privado VPN server WireGuard public key.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Privado VPN server endpoint IP and port.";
      };
      privateKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/secrets/privado_private_key";
        description = "WireGuard private key file — Pfad aus machines/<host>/profile.nix.";
      };
    };

    # 🔑 PocketID Identity Provider
    pocket-id = {
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
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── IPv6: gezielt pro Interface aus (Netbird/WG unberührt) ──────────────
    {
      boot.kernel.sysctl = lib.mkMerge (
        map (iface: {
          "net.ipv6.conf.${iface}.disable_ipv6" = lib.mkDefault 1;
          "net.ipv6.conf.${iface}.accept_ra" = lib.mkDefault 0;
          "net.ipv6.conf.${iface}.autoconf" = lib.mkDefault 0;
        }) config.my.configs.network.ipv6.disableOnInterfaces
      );
    }

    # ── TECHNITIUM DNS SERVER ─────────────────────────────────────────────────
    (lib.mkIf cfgTechnitium.enable {
      services.technitium-dns-server.enable = true;

      # systemd-resolved als DNS-Proxy:
      # Primary: 127.0.0.1 (Technitium), Fallback: DoT-Server (automatisch wenn Technitium down)
      services.resolved = {
        enable = lib.mkForce true;
        settings.Resolve = {
          DNS = "127.0.0.1";
          DNSOverTLS = "opportunistic";
          DNSSEC = "opportunistic";
          LLMNR = "no";
          MulticastDNS = "no";
          Cache = "yes";
          # FallbackDNS: DoT-Server mit TLS-Hostname für SNI-Verifikation
          FallbackDNS = lib.mkForce "1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net";
        };
      };
      # resolved verwaltet /etc/resolv.conf selbst (→ 127.0.0.53 stub)
      networking.resolvconf.enable = lib.mkForce false;
      networking.nameservers = lib.mkForce [ ];

      networking.enableIPv6 = lib.mkDefault false;

      my.impermanence.extraPaths = [ "/var/lib/technitium-dns-server" ];

      systemd.services.technitium-dns-server = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        before = lib.mkIf config.services.caddy.enable [ "caddy.service" ];
        # LogsDirectory fehlt im nixpkgs-Modul → ProtectSystem=strict blockiert /var/log-Zugriff
        serviceConfig.LogsDirectory = "technitium";
      };

      # ADR-001: DoT-only Upstream erzwingen — einmalig via API (idempotent per Marker-Datei)
      systemd.services.technitium-dns-configure =
        let
          webPort = config.my.ports."technitium-dns";
          # Technitium-API-Format: "1.1.1.1:853" (ohne "tcp-tls:" Präfix)
          dotServers = lib.concatStringsSep "," (
            map (s: lib.removePrefix "tcp-tls:" s) config.my.configs.network.dnsBootstrap
          );
          configScript = pkgs.writeShellScript "technitium-dns-configure" ''
            set -euo pipefail
            MARKER="/var/lib/technitium-dns-server/.dot-configured"
            API="http://localhost:${toString webPort}"

            if [ -f "$MARKER" ]; then
              echo "technitium-dns-configure: DoT already set (marker exists), skipping."
              exit 0
            fi

            for i in $(seq 1 30); do
              TOKEN=$(${pkgs.curl}/bin/curl -sf \
                "$API/api/user/login?user=admin&pass=admin" 2>/dev/null | \
                ${pkgs.jq}/bin/jq -r '.response.token // empty' 2>/dev/null || true)
              [ -n "$TOKEN" ] && break
              [ "$i" -eq 30 ] && {
                echo "technitium-dns-configure: API not reachable or wrong password." >&2
                echo "  → DoT forwarders NOT configured. Set manually at $API" >&2
                echo "  → Forwarders to set: ${dotServers}" >&2
                exit 0
              }
              sleep 2
            done

            ${pkgs.curl}/bin/curl -sf -X POST "$API/api/settings/set" \
              -d "token=$TOKEN&forwarders=${dotServers}&forwarderProtocol=Tls" \
              -o /dev/null
            touch "$MARKER"
            echo "technitium-dns-configure: DoT forwarders set → ${dotServers}"
          '';
        in
        {
          description = "Technitium DNS: DoT-only Forwarder konfigurieren (ADR-001)";
          after = [ "technitium-dns-server.service" ];
          wants = [ "technitium-dns-server.service" ];
          wantedBy = [ "technitium-dns-server.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = configScript;
          };
        };

      assertions = [
        {
          assertion = config.services.resolved.enable or false;
          message = "DNS: systemd-resolved muss aktiv sein (DoT-Failsafe über Technitium).";
        }
        {
          assertion = (config.services.resolved.settings.Resolve.DNSOverTLS or "no") != "no";
          message = "DNS-POLICY: services.resolved.settings.Resolve.DNSOverTLS muss 'opportunistic' oder 'yes' sein — Port 53 outbound ist nftables-gesperrt, unverschlüsseltes DNS ist verboten!";
        }
        {
          assertion = config.networking.nameservers == [ ];
          message = "DNS-POLICY: networking.nameservers muss leer sein — externe Einträge würden /etc/resolv.conf überschreiben und DoT umgehen!";
        }
        {
          assertion = config.my.configs.network.ipv6.firewall == false;
          message = "IPv6: Homelab-v4-only — my.configs.network.ipv6.firewall muss false sein.";
        }
        {
          assertion = !(config.networking.enableIPv6 or true);
          message = "IPv6: networking.enableIPv6 muss false sein — Kernel-Ebene muss IPv6 deaktivieren.";
        }
      ];
    })

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

    # ── NETBIRD SELF-HOSTED VPN ───────────────────────────────────────────────
    (lib.mkIf cfgNetbird.enable {
      services.netbird.server = {
        enable = true;
        domain = cfgNetbird.domain;
        enableNginx = false;
        management = {
          enableNginx = false;
          domain = cfgNetbird.domain;
          turnDomain = cfgNetbird.domain;
          # Lokal: pocket-id Port 1001 direkt — hairpin NAT über externe IP nicht möglich
          oidcConfigEndpoint = "http://127.0.0.1:1001/.well-known/openid-configuration";
          metricsPort = 6061;
          settings.DataStoreEncryptionKey._secret = "/var/lib/secrets/netbird-mgmt-encryption-key";
        };
        signal = {
          enableNginx = false;
          # pprof-Port des management-Binary ist hardcoded 6060 — signal auf 6062 verschieben
          metricsPort = 6062;
        };
        dashboard.settings = {
          AUTH_AUTHORITY = "https://auth.${domain}";
        };
      };

      services.netbird.clients.default = {
        interface = "wt0";
        port = 51820;
        openFirewall = true;
        login = {
          enable = true;
          setupKeyFile = cfgNetbird.setupKeyFile;
        };
      };

      networking.firewall = {
        trustedInterfaces = [ "wt0" ];
        checkReversePath = "loose";
        allowedUDPPorts = [
          3478
          10000
        ];
        allowedTCPPorts = [
          33073
          10000
        ];
      };

      my.impermanence.extraPaths = [ "/var/lib/netbird-default" ];
    })

    # ── PRIVADO VPN WIREGUARD CLIENT ──────────────────────────────────────────
    (lib.mkIf
      (config.my.services.privado-vpn.enable && !(config.my.services.vpn-confinement.enable or false))
      {
        networking.wg-quick.interfaces.privado =
          let
            ip = pkgs.iproute2;
            vpnTable = "51820";
            # Prowlarr + SABnzbd — nur Registry-UIDs über privado (Split-Tunnel)
            vpnUids = [
              config.my.users.registry.prowlarr
              config.my.users.registry.sabnzbd
            ];
            uidRules = lib.concatMapStringsSep "\n" (
              uid:
              "${ip}/bin/ip rule add uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid}"
            ) vpnUids;
            uidRulesDown = lib.concatMapStringsSep "\n" (
              uid:
              "${ip}/bin/ip rule del uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid} || true"
            ) vpnUids;
          in
          {
            autostart = true;
            address = [ config.my.services.privado-vpn.ipAddress ];
            # Split-Tunnel (table=off): kein resolv.conf via wg-quick — vermeidet resolvconf-Signatur-Konflikt
            dns = [ ];
            privateKeyFile = config.my.services.privado-vpn.privateKeyFile;
            table = "off";

            postUp = ''
              ${ip}/bin/ip route add default dev privado table ${vpnTable}
              ${uidRules}
            '';
            preDown = ''
              ${uidRulesDown}
              ${ip}/bin/ip route flush table ${vpnTable} || true
            '';

            peers = [
              {
                publicKey = config.my.services.privado-vpn.publicKey;
                endpoint = config.my.services.privado-vpn.endpoint;
                allowedIPs = [ "0.0.0.0/0" ];
                persistentKeepalive = 25;
              }
            ];
          };
      }
    )

    # ── POCKETID IDENTITY PROVIDER ────────────────────────────────────────────
    (lib.mkIf config.my.services.pocket-id.enable {
      systemd.services.pocket-id = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      # Pocket-ID nutzt Port 1001 (< 1024) ohne Root — Kernel-Schwelle absenken
      boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = lib.mkDefault 1000;

      services.pocket-id = {
        enable = true;
        dataDir = config.my.services.pocket-id.dataDir;
        settings = {
          PORT = toString config.my.services.pocket-id.port;
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
          ReadWritePaths = [ config.my.services.pocket-id.dataDir ];
        }
        (lib.mkIf (config.my.services.pocket-id.secretsFile != "") {
          EnvironmentFile = lib.mkAfter [ "-${config.my.services.pocket-id.secretsFile}" ];
        })
      ];

      my.impermanence.extraPaths = [
        config.my.services.pocket-id.dataDir
      ];
    })

    # ── CADDY GLOBAL CONFIG & SNIPPETS ────────────────────────────────────────
    # ADR 018: Dual-Log — default-Logger (stdout→journald→CrowdSec) bleibt unverändert.
    # dsgvo_access-Logger abonniert http.log.access (alle vHosts) und schreibt
    # IP-maskierte Logs auf /24 (IPv4) / /48 (IPv6) nach /var/log/caddy/dsgvo.json.
    {
      services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
        servers {
          trusted_proxies static private_ranges
          timeouts {
            read_body   30s
            read_header 10s
            idle        5m
          }
        }

        log dsgvo_access {
          include http.log.access
          output file /var/log/caddy/dsgvo.json {
            roll_size 100mb
            roll_keep 14
            roll_keep_for 720h
          }
          format filter {
            wrap json
            fields {
              request>remote_ip ip_mask {
                ipv4 24
                ipv6 48
              }
              request>client_ip ip_mask {
                ipv4 24
                ipv6 48
              }
            }
          }
          level INFO
        }
      '';

      services.caddy.logFormat = lib.mkIf config.services.caddy.enable (
        lib.mkForce ''
          level INFO
          output stdout
          format json
        ''
      );
      services.caddy.extraConfig = lib.mkIf config.services.caddy.enable (
        lib.mkBefore caddySnippets.extraConfig
      );

      systemd.tmpfiles.rules = lib.mkIf config.services.caddy.enable [
        "d /var/log/caddy 0750 caddy caddy -"
      ];
    }
  ];
}
