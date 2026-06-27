# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Blocky DNS, Valkey, PostgreSQL, Tailscale, Pocket-ID, Privado
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
#     - docs/adr/002-ipv6-homelab-v4-only.md
#     - docs/AUDIT-blocky-caddy-ipv6.md
#   lib:
#     - lib/dns-policy.nix
#     - lib/memory-policy.nix
#     - lib/critical-systemd.nix
#   services:
#     - blocky
#     - postgresql
#     - redis-valkey
#     - tailscaled
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
}: let
  cfgTechnitium = config.my.services.technitium-dns-server;
  cfgValkey = config.my.services.valkey;
  cfgPostgres = config.my.services.postgresql;
  ramGB = config.my.configs.hardware.ramGB;
  sockets = import ../../lib/unix-sockets.nix {inherit lib;};

  lanIP = config.my.configs.server.lanIP;
  dnsPolicy = import ../../lib/dns-policy.nix {inherit lib;};
  memory = import ../../lib/memory-policy.nix {inherit lib;};
  criticalSystemd = import ../../lib/critical-systemd.nix {
    inherit lib;
    oomScore = -1000;
  };
  domain = config.my.configs.identity.domain;
  caddySnippets = import ../../lib/caddy-snippets.nix {
    inherit lib;
    pocketIdPort =
      if config.my.services.pocket-id.enable or false
      then config.my.ports.pocket-id
      else null;
    lanCidr = "192.168.0.0/16";
  };
in {
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    technitium-dns-server.enable = lib.mkEnableOption "Technitium DNS Server";
    valkey.enable = lib.mkEnableOption "Valkey cache server (Redis-fork)";
    postgresql.enable = lib.mkEnableOption "PostgreSQL database server";

    # 🛑 Blocky DNS Resolver
    blocky = {
      enable = lib.mkEnableOption "Blocky DNS Resolver";
      port = lib.mkOption {
        type = lib.types.port;
        default = 53;
        description = "Blocky DNS listening port.";
      };
      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 4000;
        description = "Blocky HTTP metrics port.";
      };
      upstreamDns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "tcp-tls:1.1.1.1:853"
          "tcp-tls:9.9.9.9:853"
          "tcp-tls:149.112.112.112:853"
        ];
        description = "Blocky-Upstreams — nur DoT (tcp-tls:host:853), DoH (https://…) oder DoQ.";
      };
      enableBlocking = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "DNS-Blocklists (StevenBlack etc.) — Adblock in Blocky, nicht nftables.";
      };
      blockingLists = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            "https://adaway.org/hosts.txt"
          ];
          tracking = [
            "https://v.firebog.net/hosts/Easyprivacy.txt"
          ];
        };
        description = "Blocky denylists — Gruppenname → URL-Liste.";
      };
    };

    # 🔗 Tailscale VPN
    tailscale = {
      enable = lib.mkEnableOption "Tailscale Zero-Trust VPN";
      port = lib.mkOption {
        type = lib.types.port;
        default = 41641;
        description = "Tailscale UDP WireGuard port.";
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
        default = ["10.255.255.255"];
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
    # ── IPv6: gezielt pro Interface aus (Tailscale/WG unberührt) ─────────────
    {
      boot.kernel.sysctl = lib.mkMerge (
        map (iface: {
          "net.ipv6.conf.${iface}.disable_ipv6" = lib.mkDefault 1;
          "net.ipv6.conf.${iface}.accept_ra" = lib.mkDefault 0;
          "net.ipv6.conf.${iface}.autoconf" = lib.mkDefault 0;
        })
        config.my.configs.network.ipv6.disableOnInterfaces
      );
    }

    # ── TECHNITIUM DNS SERVER ─────────────────────────────────────────────────
    (lib.mkIf cfgTechnitium.enable {
      services.technitium-dns-server.enable = true;
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
        RestrictAddressFamilies = ["AF_UNIX"];
        ReadWritePaths = ["/var/lib/redis-valkey"];
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
          RestrictAddressFamilies = ["AF_UNIX"];
          ReadWritePaths = ["/var/lib/postgresql"];
        }
      ];
    })

    # ── BLOCKY DNS RESOLVER ───────────────────────────────────────────────────
    (lib.mkIf config.my.services.blocky.enable {
      services.resolved.enable = lib.mkForce false;

      my.impermanence.extraPaths = ["/var/lib/blocky"];

      systemd.tmpfiles.rules = [
        "d /var/lib/blocky 0755 root root -"
      ];

      services.blocky = {
        enable = true;
        settings =
          {
            connectIPVersion = "v4";
            ports = {
              dns = config.my.services.blocky.port;
              http = config.my.services.blocky.metricsPort;
            };
            upstreams.groups.default = config.my.services.blocky.upstreamDns;
            bootstrapDns = config.my.configs.network.dnsBootstrap;
            dnssec = {
              validate = true;
            };
            filtering = {
              queryTypes = ["AAAA"];
            };
            customDNS = {
              mapping = {
                "nixhome.local" = lanIP;
                "${domain}" = lanIP;
                "*.${domain}" = lanIP;
              };
            };
          }
          // lib.optionalAttrs config.my.services.blocky.enableBlocking {
            blocking = {
              denylists = config.my.services.blocky.blockingLists;
              clientGroupsBlock.default = lib.attrNames config.my.services.blocky.blockingLists;
            };
          };
      };

      networking.enableIPv6 = lib.mkDefault false;
      networking.nameservers = lib.mkForce ["127.0.0.1"];

      networking.resolvconf.enable = lib.mkForce false;

      environment.etc."resolv.conf".text = ''
        # NixOS/Blocky — nur lokaler Resolver (DoT egress via Blocky)
        nameserver 127.0.0.1
      '';

      assertions = [
        {
          assertion = dnsPolicy.allEncrypted config.my.services.blocky.upstreamDns;
          message = "DNS: Blocky-Upstreams müssen verschlüsselt sein (tcp-tls:/https://) — kein Klartext.";
        }
        {
          assertion = dnsPolicy.allEncrypted config.my.configs.network.dnsBootstrap;
          message = "DNS: Blocky-Bootstrap muss verschlüsselt sein — kein Klartext.";
        }
        {
          assertion = dnsPolicy.nonePlaintext config.my.services.blocky.upstreamDns;
          message = "DNS: Klartext-Upstreams in blocky.upstreamDns erkannt.";
        }
        {
          assertion = config.networking.nameservers == ["127.0.0.1"];
          message = "DNS: resolv.conf darf nur 127.0.0.1 (Blocky) — kein 1.1.1.1-Bypass.";
        }
        {
          assertion = config.my.configs.network.ipv6.firewall == false;
          message = "IPv6: Homelab-v4-only — my.configs.network.ipv6.firewall muss false sein.";
        }
        {
          assertion = !(config.networking.enableIPv6 or true);
          message = "IPv6: networking.enableIPv6 muss false sein — Kernel-Ebene muss IPv6 deaktivieren.";
        }
        {
          assertion = lib.length config.my.services.blocky.upstreamDns >= 3;
          message = "DNS: Mindestens 3 DoT-Upstream-Server erforderlich (aktuell: ${toString (lib.length config.my.services.blocky.upstreamDns)}).";
        }
        {
          assertion = lib.length config.my.configs.network.dnsBootstrap >= 3;
          message = "DNS: Mindestens 3 Bootstrap-DoT-Server erforderlich (aktuell: ${toString (lib.length config.my.configs.network.dnsBootstrap)}).";
        }
        {
          assertion = lib.all (s: lib.hasPrefix "tcp-tls:" s) config.my.services.blocky.upstreamDns;
          message = "DNS: Alle Blocky-Upstreams müssen tcp-tls:-Format haben — kein https:// oder Klartext.";
        }
        {
          assertion = lib.all (s: lib.hasPrefix "tcp-tls:" s) config.my.configs.network.dnsBootstrap;
          message = "DNS: Alle Bootstrap-Upstreams müssen tcp-tls:-Format haben — kein https:// oder Klartext.";
        }
      ];

      systemd.services.blocky = {
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        before = lib.mkIf config.services.caddy.enable ["caddy.service"];
      };

      systemd.services.blocky.serviceConfig = lib.mkMerge [
        criticalSystemd
        {
          ProtectSystem = lib.mkDefault "strict";
          ProtectHome = lib.mkDefault true;
          PrivateTmp = lib.mkDefault true;
          PrivateDevices = lib.mkDefault true;
          ProtectHostname = lib.mkDefault true;
          ProtectClock = lib.mkDefault true;
          ProtectKernelTunables = lib.mkDefault true;
          ProtectKernelModules = lib.mkDefault true;
          ProtectControlGroups = lib.mkDefault true;
          RestrictNamespaces = lib.mkDefault true;
          NoNewPrivileges = lib.mkDefault true;
          PrivateNetwork = lib.mkDefault false;
          RestrictAddressFamilies = lib.mkDefault (
            if config.my.configs.network.ipv6.firewall
            then [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ]
            else [
              "AF_INET"
              "AF_UNIX"
            ]
          );
          CapabilityBoundingSet = lib.mkDefault ["CAP_NET_BIND_SERVICE"];
          AmbientCapabilities = lib.mkDefault ["CAP_NET_BIND_SERVICE"];
          SystemCallFilter = lib.mkDefault [
            "@system-service"
            "~@privileged"
            "~@resources"
            "~@mount"
          ];
          LockPersonality = lib.mkDefault true;
          RestrictRealtime = lib.mkDefault true;
          RestrictSUIDSGID = lib.mkDefault true;
          ReadWritePaths = lib.mkDefault ["/var/lib/blocky"];
          MemoryHigh = lib.mkDefault "200M";
          MemoryMax = lib.mkDefault "500M";
        }
      ];
    })

    # ── TAILSCALE VPN ─────────────────────────────────────────────────────────
    (lib.mkIf config.my.services.tailscale.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/secrets 0700 root root -"
      ];

      services.tailscale = {
        enable = true;
        openFirewall = true;
        port = config.my.services.tailscale.port;
        permitCertUid = "caddy";
        useRoutingFeatures = "client";
        # DNS bleibt bei Blocky (127.0.0.1) — kein Tailscale MagicDNS in resolv.conf
        extraUpFlags = [
          "--ssh"
          "--accept-dns=false"
          "--accept-routes=true"
        ];
      };
      networking.firewall.trustedInterfaces = ["tailscale0"];
      networking.firewall.checkReversePath = "loose";

      systemd.services.tailscale-autoconnect = {
        description = "Automatic Tailscale Login";
        after = [
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [
          "tailscaled.service"
          "network-online.target"
        ];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "tailscale-auth" ''
            sleep 2
            TOKEN_FILE=''${TOKEN_FILE:-/var/lib/secrets/tailscale_token}
            if [ ! -f "$TOKEN_FILE" ]; then
              echo "tailscale-autoconnect: kein $TOKEN_FILE — manuell: tailscale up"
              exit 0
            fi
            status=$(${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r .BackendState)
            if [ "$status" = "NeedsLogin" ] || [ "$status" = "Stopped" ]; then
              ${pkgs.tailscale}/bin/tailscale up --authkey="$(cat "$TOKEN_FILE")"
            fi
          '';
        };
      };

      systemd.services.tailscaled = {
        stopIfChanged = false;
        serviceConfig = {
          Restart = "always";
          RestartSec = "2s";
          OOMScoreAdjust = -1000;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
          ];
        };
      };
    })

    # ── PRIVADO VPN WIREGUARD CLIENT ──────────────────────────────────────────
    (
      lib.mkIf
      (config.my.services.privado-vpn.enable && !(config.my.services.vpn-confinement.enable or false))
      {
        networking.wg-quick.interfaces.privado = let
          ip = pkgs.iproute2;
          vpnTable = "51820";
          # Prowlarr + SABnzbd — nur Registry-UIDs über privado (Split-Tunnel)
          vpnUids = [
            config.my.users.registry.prowlarr
            config.my.users.registry.sabnzbd
          ];
          uidRules =
            lib.concatMapStringsSep "\n" (
              uid: "${ip}/bin/ip rule add uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid}"
            )
            vpnUids;
          uidRulesDown =
            lib.concatMapStringsSep "\n" (
              uid: "${ip}/bin/ip rule del uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid} || true"
            )
            vpnUids;
        in {
          autostart = true;
          address = [config.my.services.privado-vpn.ipAddress];
          # Split-Tunnel (table=off): kein resolv.conf via wg-quick — vermeidet resolvconf-Signatur-Konflikt
          dns = [];
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
              allowedIPs = ["0.0.0.0/0"];
              persistentKeepalive = 25;
            }
          ];
        };
      }
    )

    # ── POCKETID IDENTITY PROVIDER ────────────────────────────────────────────
    (lib.mkIf config.my.services.pocket-id.enable {
      systemd.services.pocket-id = {
        after = [
          "postgresql.service"
          "network-online.target"
        ];
        wants = [
          "postgresql.service"
          "network-online.target"
        ];
      };

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
        (memory.pocketId {})
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
          ReadWritePaths = [config.my.services.pocket-id.dataDir];
        }
        (lib.mkIf (config.my.services.pocket-id.secretsFile != "") {
          EnvironmentFile = lib.mkAfter ["-${config.my.services.pocket-id.secretsFile}"];
        })
      ];

      my.impermanence.extraPaths = [
        config.my.services.pocket-id.dataDir
      ];
    })

    # ── CADDY GLOBAL CONFIG & SNIPPETS ────────────────────────────────────────
    {
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
    }
  ];
}
