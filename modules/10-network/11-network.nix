# Valkey + PostgreSQL → 15-databases.nix
# Netbird + Privado VPN → 16-vpn.nix
# Pocket-ID → 17-pocket-id.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgTechnitium = config.my.services.technitium-dns-server;
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
  options.my.services.technitium-dns-server.enable = lib.mkEnableOption "Technitium DNS Server";

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
