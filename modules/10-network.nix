# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures local networking infrastructure and central database plumbing, 
# including Valkey (Redis-fork) cache.
# Key decisions -> ADR-10-network.md

{ config, lib, pkgs, ... }:

let
  cfgValkey = config.my.services.valkey;
  cfgBlocky = config.my.services.blocky;
  cfgPrivado = config.my.services.privado-vpn;
  cfgTailscale = config.my.services.tailscale;

  lanIP = config.my.configs.server.lanIP;
  tailscaleIP = config.my.configs.server.tailscaleIP;
  dnsDoH = config.my.configs.network.dnsDoH;
  dnsBootstrap = config.my.configs.network.dnsBootstrap;
  domain = config.my.configs.identity.domain;
  portValkey = config.my.ports.valkey;

  caddy = import ../lib/caddy-helpers.nix { inherit lib; };
  caddySnippets = import ../lib/caddy-snippets.nix {
    inherit lib;
    pocketIdPort =
      if config.my.services.pocket-id.enable or false then config.my.ports.pocket-id
      else null;
    lanCidr = "192.168.0.0/16";
  };

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    valkey.enable = lib.mkEnableOption "Valkey cache server (Redis-fork)";

    # ðŸ›‘ Blocky DNS Resolver
    blocky = {
      enable = lib.mkEnableOption "Blocky DNS Resolver";
      port = lib.mkOption { type = lib.types.port; default = 53; description = "Blocky DNS listening port."; };
      metricsPort = lib.mkOption { type = lib.types.port; default = 4000; description = "Blocky HTTP metrics port."; };
      upstreamDns = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" "8.8.8.8" ]; description = "List of upstream DNS servers."; };
    };

    # ðŸ”— Tailscale VPN
    tailscale = {
      enable = lib.mkEnableOption "Tailscale Zero-Trust VPN";
      port = lib.mkOption { type = lib.types.port; default = 41641; description = "Tailscale UDP WireGuard port."; };
    };

    # ðŸ›¡ï¸ Privado VPN WireGuard Client
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
        default = "/home/moritz/secrets/privado_private_key";
        description = "WireGuard private key file â€” Pfad aus machines/<host>/profile.nix.";
      };
    };

    # ðŸ”‘ PocketID Identity Provider
    pocket-id = {
      enable = lib.mkEnableOption "PocketID OIDC Passkey Provider";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.pocket-id; description = "PocketID web interface listening port."; };
      dataDir = lib.mkOption { type = lib.types.str; default = "/data/state/pocket-id"; description = "Database state directory."; };
      secretsFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional env file (ENCRYPTION_KEY=â€¦) â€” Pfad aus machines/<host>/profile.nix.";
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    {
      # Admin Hangar Loopback Alias
      networking.interfaces.lo.ipv4.addresses = [{ address = "127.0.0.2"; prefixLength = 8; }];
    }

    # ── VALKEY CACHE DATABASE (Valkey package inside Redis module) ────────────
    (lib.mkIf cfgValkey.enable {
      systemd.tmpfiles.rules = [
        "d /data/state/valkey 0750 redis redis -"
      ];

      services.redis = {
        package = pkgs.valkey;
        servers.valkey = {
          enable = true;
          bind = "127.0.0.1"; # Lokal isolierter Ingress
          port = 0; # TCP deaktiviert, nur Unix Sockets
          openFirewall = false;
          unixSocket = "/run/redis-valkey/valkey.sock";
          unixSocketPerm = 660;
          settings = {
            dir = "/data/state/valkey";
            maxmemory = "512mb"; # Puffer für große Paperless OCR Bulk-Imports
            maxmemory-policy = "volatile-lru"; # Schützt aktive Paperless Tasks vor LRU-Löschung
            save = ""; # Pure In-Memory für minimalen SSD-Verschleiß
          };
        };
      };

      # Valkey Server Sandboxing
      systemd.services.redis-valkey.serviceConfig = {
        OOMScoreAdjust = -1000; # Kritischer Cache/Message-Broker: Niemals von OOM-Killer beenden
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [ "AF_UNIX" ]; # Admin Hangar Isolation
        ReadWritePaths = [ "/data/state/valkey" ];
      };
    })

    # ── BLOCKY DNS RESOLVER ───────────────────────────────────────────────────
    (lib.mkIf config.my.services.blocky.enable {
      services.resolved.enable = lib.mkForce false;

      systemd.tmpfiles.rules = [
        "d /var/lib/blocky 0755 root root -"
      ];

      services.blocky = {
        enable = true;
        settings = {
          ports = {
            dns = config.my.services.blocky.port;
            http = config.my.services.blocky.metricsPort;
          };
          upstreams.groups.default = config.my.services.blocky.upstreamDns;
          bootstrapDns = config.my.configs.network.dnsBootstrap;
          customDNS = {
            mapping = {
              "nixhome.local" = lanIP;
              "${domain}" = lanIP;
              "*.${domain}" = lanIP;
            };
          };
        };
      };

      networking.nameservers = lib.mkForce [ "127.0.0.1" "1.1.1.1" ];

      systemd.services.blocky = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        before = lib.mkIf config.services.caddy.enable [ "caddy.service" ];
      };

      systemd.services.blocky.serviceConfig = {
        OOMScoreAdjust = -1000;
        Restart = lib.mkDefault "always";
        RestartSec = lib.mkDefault "5s";
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
        RestrictAddressFamilies = lib.mkDefault [ "AF_UNIX" ]; # Admin Hangar Isolation
        CapabilityBoundingSet = lib.mkDefault [ "CAP_NET_BIND_SERVICE" ];
        AmbientCapabilities = lib.mkDefault [ "CAP_NET_BIND_SERVICE" ];
        SystemCallFilter = lib.mkDefault [
          "@system-service"
          "~@privileged"
          "~@resources"
          "~@mount"
        ];
        LockPersonality = lib.mkDefault true;
        RestrictRealtime = lib.mkDefault true;
        RestrictSUIDSGID = lib.mkDefault true;
        ReadWritePaths = lib.mkDefault [ "/var/lib/blocky" ];
        MemoryHigh = lib.mkDefault "200M";
        MemoryMax = lib.mkDefault "500M";
      };
    })

    # â”€â”€ TAILSCALE VPN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        # DNS bleibt bei Blocky (127.0.0.1) â€” kein Tailscale MagicDNS in resolv.conf
        extraUpFlags = [ "--ssh" "--accept-dns=false" "--accept-routes=true" ];
      };
            networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 80 443 ];
      networking.firewall.checkReversePath = "loose";

      systemd.services.tailscale-autoconnect = {
        description = "Automatic Tailscale Login";
        after = [ "tailscaled.service" "network-online.target" ];
        wants = [ "tailscaled.service" "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "tailscale-auth" ''
            sleep 2
            TOKEN_FILE=''${TOKEN_FILE:-/home/moritz/secrets/tailscale_token}
            if [ ! -f "$TOKEN_FILE" ]; then
              echo "tailscale-autoconnect: kein $TOKEN_FILE â€” manuell: tailscale up"
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
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        };
      };
    })

    # â”€â”€ PRIVADO VPN WIREGUARD CLIENT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    (lib.mkIf config.my.services.privado-vpn.enable {


      networking.wg-quick.interfaces.privado =
        let
          ip = pkgs.iproute2;
          vpnTable = "51820";
          # Prowlarr 969, SABnzbd 984 â€” nur diese UIDs Ã¼ber privado (Split-Tunnel)
          vpnUids = [ 969 984 ];
          uidRules = lib.concatMapStringsSep "\n"
            (uid:
              "${ip}/bin/ip rule add uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid}"
            )
            vpnUids;
          uidRulesDown = lib.concatMapStringsSep "\n"
            (uid:
              "${ip}/bin/ip rule del uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid} || true"
            )
            vpnUids;
        in
        {
          autostart = true;
          address = [ config.my.services.privado-vpn.ipAddress ];
          dns = config.my.services.privado-vpn.dns;
          privateKeyFile = config.my.services.privado-vpn.privateKeyFile;
          table = "off";

          postUp = ''
            ${ip}/bin/ip route add default dev privado table ${vpnTable}
            ${uidRules}
          '';
          preDown = ''
            ${uidRulesDown}
            ${ip}/bin/ip route flush table ${vpnTable} || true
            ${pkgs.openresolv}/bin/resolvconf -d privado 2>/dev/null || true
          '';

          peers = [{
            publicKey = config.my.services.privado-vpn.publicKey;
            endpoint = config.my.services.privado-vpn.endpoint;
            allowedIPs = [ "0.0.0.0/0" ];
            persistentKeepalive = 25;
          }];
        };


    })

    # â”€â”€ POCKETID IDENTITY PROVIDER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    (lib.mkIf config.my.services.pocket-id.enable {
      systemd.services.pocket-id = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

      services.pocket-id = {
        enable = true;
        dataDir = config.my.services.pocket-id.dataDir;
        settings = {
          HOST = "127.0.0.1";
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
          OOMScoreAdjust = -900;
        }
        (lib.mkIf (config.my.services.pocket-id.secretsFile != "") {
          EnvironmentFile = lib.mkAfter [ "-${config.my.services.pocket-id.secretsFile}" ];
        })
      ];

      services.caddy.virtualHosts."auth.${domain}" = {
        extraConfig = caddy.proxySecurity config.my.services.pocket-id.port;
      };
    })

    # â”€â”€ CADDY GLOBAL CONFIG & SNIPPETS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    {
      systemd.services.caddy = lib.mkIf config.services.caddy.enable {
        serviceConfig = {
          OOMScoreAdjust = -1000;
          Nice = -10;
          CPUWeight = 10000;
          LimitNOFILE = 1048576;
        };
      };

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

      services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
        admin "unix//run/caddy-admin.sock"
      '';

      # â”€â”€ LEBENSVERSICHERUNG: SYSTEMD-NETWORKD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      # "Gott-Modus" fÃ¼r den Netzwerk-Daemon: SchÃ¼tzt vor dem OOM-Killer und 
      # gewÃ¤hrt hÃ¶chste CPU-PrioritÃ¤t, damit der Server bei Lastspitzen nicht 
      # die Verbindung verliert.
      systemd.services.systemd-networkd.serviceConfig = {
        OOMScoreAdjust = -1000;
        CPUSchedulingPolicy = "rr";
        CPUSchedulingPriority = 99;
      };
      # =====================================================================
      # Nativer Cloudflare DDNS Service
      # =====================================================================
      services.cloudflare-dyndns = {
        enable = true;
        domains = [ "${domain}" "*.${domain}" ];
        apiTokenFile = "/home/moritz/secrets/ddclient.env"; # Cloudflare API Token
      };

      systemd.services.cloudflare-dyndns = {
        serviceConfig = {
          OOMScoreAdjust = -1000;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          MemoryDenyWriteExecute = true;
        };
      };

      boot.kernel.sysctl = {
        # High-Performance TCP Routing (BBR) -> Verhindert Ruckeln bei Media Streaming über WAN / Tailscale
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.core.default_qdisc" = "fq";
        # Swappiness: System zwingen, eher File-Cache aufzugeben als App-Memory zu swappen
        "vm.swappiness" = 10;
      };

    }
  ];
}








