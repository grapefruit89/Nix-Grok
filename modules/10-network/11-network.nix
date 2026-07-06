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
    pocketIdPort =
      if config.my.services.pocket-id.enable or false then config.my.ports.pocket-id else null;
    lanCidr = "192.168.0.0/16";
    oauth2proxyPort = if config.my.services.oauth2-proxy.enable or false then 4180 else null;
    oauth2Domain = config.my.configs.identity.domain;
  };
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services.technitium-dns-server = {
    enable = lib.mkEnableOption "Technitium DNS Server";
    splitHorizon = {
      enable = lib.mkEnableOption "Split-Horizon DNS: *.domain → LAN-IP via Technitium";
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
    # ADR-1001: DNS-over-TLS Architektur
    #
    # HOST-DNS (kein Chicken-Egg-Problem):
    #   resolved → DoT direkt (8 Server, deklarativ) — KEINE Abhängigkeit von Technitium
    #
    # LAN-CLIENTS:
    #   → Technitium (127.0.0.1:53 / LAN-IP:53)
    #   → Technitium leitet weiter zu DoT (8 Server, via API konfiguriert, non-critical)
    #
    # Technitium-Rolle: split-horizon (zukünftig deklarativ), LAN-DNS, Web-UI
    # Technitium-Ausfall: host-DNS läuft weiter via resolved-DoT, LAN-Clients betroffen
    (lib.mkIf cfgTechnitium.enable (
      let
        dot = config.my.configs.network.dnsBootstrap;
        # resolved-Format: "IP#TLS-Hostname IP#TLS-Hostname ..."
        resolvedDns = lib.concatStringsSep " " (map (s: "${s.ip}#${s.hostname}") dot);
        # Technitium-API-Format: "IP:853,IP:853,..."
        dotServers = lib.concatStringsSep "," (map (s: "${s.ip}:853") dot);
        webPort = config.my.ports."technitium-dns";
        domain = config.my.configs.identity.domain;
        lanIp = config.my.configs.server.lanIP;
        splitHorizonEnabled = config.my.services.technitium-dns-server.splitHorizon.enable;

        configScript = pkgs.writeShellScript "technitium-dns-configure" ''
          set -euo pipefail
          API="http://localhost:${toString webPort}"
          CURL="${pkgs.curl}/bin/curl"
          JQ="${pkgs.jq}/bin/jq"

          # ── Login ──────────────────────────────────────────────────────────
          for i in $(seq 1 30); do
            TOKEN=$($CURL -sf "$API/api/user/login?user=admin&pass=admin" 2>/dev/null | \
              $JQ -r '.response.token // empty' 2>/dev/null || true)
            [ -n "$TOKEN" ] && break
            [ "$i" -eq 30 ] && {
              echo "technitium-dns-configure: WARNING — API nicht erreichbar." >&2
              echo "  Host-DNS laeuft weiter via resolved-DoT." >&2
              exit 0
            }
            sleep 2
          done

          # ── DoT-Forwarder: prüfe ob bereits gesetzt (API-State, kein Marker) ──
          CURRENT=$($CURL -sf "$API/api/settings/get?token=$TOKEN" 2>/dev/null | \
            $JQ -r '.response.dnsServerDomainName // ""' 2>/dev/null || echo "")
          CURRENT_FWD=$($CURL -sf "$API/api/settings/get?token=$TOKEN" 2>/dev/null | \
            $JQ -r '[.response.forwarders[]?.nameServer] | join(",") // ""' 2>/dev/null || echo "")
          WANT_FWD="${dotServers}"

          if [ "$CURRENT_FWD" != "$WANT_FWD" ]; then
            $CURL -sf -X POST "$API/api/settings/set" \
              -d "token=$TOKEN&forwarders=$WANT_FWD&forwarderProtocol=Tls" \
              -o /dev/null
            echo "technitium-dns-configure: DoT-Forwarder gesetzt → $WANT_FWD"
          else
            echo "technitium-dns-configure: DoT-Forwarder bereits korrekt, kein Update."
          fi

          ${lib.optionalString splitHorizonEnabled ''
            # ── Split-Horizon Zone: prüfe ob bereits vorhanden (API-State) ─────
            ZONE_EXISTS=$($CURL -sf "$API/api/zones/list?token=$TOKEN" 2>/dev/null | \
              $JQ -r '.response.zones[]? | select(.name == "${domain}") | .name' 2>/dev/null || echo "")

            if [ -z "$ZONE_EXISTS" ]; then
              echo "technitium-dns-configure: Split-Horizon Zone ${domain} anlegen..."
              $CURL -sf -X POST "$API/api/zones/create" \
                -d "token=$TOKEN&zone=${domain}&type=Primary" -o /dev/null
              $CURL -sf -X POST "$API/api/zones/records/add" \
                -d "token=$TOKEN&zone=${domain}&domain=*.${domain}&type=A&ipAddress=${lanIp}&ttl=300" \
                -o /dev/null
              echo "technitium-dns-configure: *.${domain} → ${lanIp} (300s TTL)"
            else
              echo "technitium-dns-configure: Split-Horizon Zone ${domain} bereits vorhanden."
            fi
          ''}
        '';
      in
      {
        services.technitium-dns-server.enable = true;

        # resolved → DoT direkt (kein Technitium-Umweg, kein Chicken-Egg-Problem)
        # DNSOverTLS=yes: strict — niemals Plaintext-Fallback
        services.resolved = {
          enable = lib.mkForce true;
          settings.Resolve = {
            DNS = resolvedDns;
            DNSOverTLS = "yes";
            DNSSEC = "allow-downgrade";
            LLMNR = "no";
            MulticastDNS = "no";
            Cache = "yes";
            FallbackDNS = "";
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
          serviceConfig = {
            # LogsDirectory fehlt im nixpkgs-Modul → ProtectSystem=strict blockiert /var/log-Zugriff
            LogsDirectory = "technitium";
            # LAN-DNS für alle Clients — Ausfall trifft das gesamte LAN.
            # Nicht -900 weil Host selbst via resolved→DoT unabhängig weiterläuft.
            OOMScoreAdjust = lib.mkDefault (-300);
          };
        };

        # Technitium LAN-DoT + Split-Horizon konfigurieren (non-critical für Host-DNS)
        systemd.services.technitium-dns-configure = {
          description = "Technitium DNS: DoT-Forwarder + Split-Horizon Zone";
          after = [ "technitium-dns-server.service" ];
          wants = [ "technitium-dns-server.service" ];
          wantedBy = [ "technitium-dns-server.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = configScript;
          };
        };

        # Split-Horizon HOST: /etc/hosts Einträge aus services.spec (NSS vor DNS)
        # Kein API-Call, kein Dummy-Interface — 100% deklarativ in Nix.
        # Jeder Dienst in services.spec bekommt automatisch einen /etc/hosts-Eintrag.
        # LAN-Clients: Technitium-Zone (API-basiert, nicht-kritisch wegen NAT-Hairpin).
        networking.extraHosts = lib.mkIf splitHorizonEnabled (
          let
            fqdns = lib.concatStringsSep " " (
              lib.mapAttrsToList (
                _name: entry: lib.optionalString (entry.subdomain != null) "${entry.subdomain}.${domain}"
              ) config.my.services.spec
            );
          in
          lib.optionalString (fqdns != "") "${lanIp} ${fqdns}"
        );

        assertions = [
          {
            assertion = config.services.resolved.enable or false;
            message = "DNS: systemd-resolved muss aktiv sein (direkt DoT ohne Technitium-Umweg).";
          }
          {
            assertion = (config.services.resolved.settings.Resolve.DNSOverTLS or "no") == "yes";
            message = "DNS-POLICY: DNSOverTLS muss 'yes' (strict) sein — Host-DNS geht direkt an DoT-Upstreams, kein Plaintext-Fallback erlaubt!";
          }
          {
            assertion = (config.services.resolved.settings.Resolve.DNS or "") != "127.0.0.1";
            message = "DNS-POLICY: resolved darf nicht 127.0.0.1 (Technitium) als primary DNS nutzen — direkt DoT verwenden!";
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
      }
    ))

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
