# ---
# schema: "109x=Infrastruktur-Band (kein Service-Port)"
# meta:
#   layer: 3
#   role: module
#   purpose: Host-DNS (DoT via resolved), Caddy global config + Snippets, IPv6-Deaktivierung
#   lib:
#     - lib/caddy-snippets.nix
#     - lib/assertions.nix
#   docs:
#     - docs/adr/1001-dns-dot-fail-closed.md
#     - docs/adr/1002-ipv6-homelab-v4-only.md
#     - docs/adr/1014-caddy-security-headers-trusted-proxies.md
#     - docs/adr/1018-caddy-dual-log-dsgvo.md
#   tags:
#     - dns
#     - caddy
#     - network
# ---
# Valkey + PostgreSQL → 1095-databases.nix
# Netbird + Privado VPN → 1096-vpn.nix
# Pocket-ID → 1001-pocket-id.nix
# Blocky DNS → 1002-blocky.nix
{
  config,
  lib,
  ...
}:
let
  asserts = import ../../lib/assertions.nix { inherit lib; };
  caddySnippets = import ../../lib/caddy-snippets.nix {
    pocketIdPort =
      if config.my.services.pocket-id.enable or false then config.my.ports.pocket-id else null;
    lanCidr = builtins.concatStringsSep " " config.my.security.firewall.lanCidrs;
    netbirdCidr = config.my.configs.network.netbirdCidr;
    oauth2proxyPort =
      if config.my.services.oauth2-proxy.enable or false then config.my.ports.oauth2-proxy else null;
    oauth2Domain = config.my.configs.identity.domain;
  };
  dot = config.my.configs.network.dnsBootstrap;
  resolvedDns = lib.concatStringsSep " " (map (s: "${s.ip}#${s.hostname}") dot);
  domain = config.my.configs.identity.domain;
  lanIp = config.my.configs.server.lanIP;
in
{
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

    # ── HOST-DNS: resolved → DoT (direkt, kein Blocky-Umweg) ─────────────────
    # ADR-1001: Host-DNS hat keine Abhängigkeit von Blocky — kein Chicken-Egg-Problem.
    # DNSOverTLS=yes: strict — niemals Plaintext-Fallback erlaubt.
    {
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
      networking.resolvconf.enable = lib.mkForce false;
      networking.nameservers = lib.mkForce [ ];
      networking.enableIPv6 = lib.mkDefault false;

      # Split-Horizon für Host via /etc/hosts (NSS vor DNS — Host nutzt resolved, nicht Blocky).
      networking.extraHosts = lib.mkIf config.my.services.blocky.enable (
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
        (asserts.mkAssert {
          code = "DNS-001";
          was = "services.resolved.enable ist nicht gesetzt — systemd-resolved ist inaktiv";
          warum = "ADR-003: Alle DNS-Anfragen über DoT (Cloudflare 1.1.1.1#one.one.one.one). Nur resolved implementiert DNSOverTLS=yes systemweit. dnsmasq/bind sind verboten (lib/forbidden-tech.nix).";
          beheben = "services.resolved.enable = true; setzen. networking.nameservers = []; sicherstellen.";
          assertion = config.services.resolved.enable or false;
        })
        (asserts.mkAssert {
          code = "DNS-002";
          was = "services.resolved.settings.Resolve.DNSOverTLS ist nicht 'yes' (strict mode)";
          warum = "ADR-003: 'opportunistic' erlaubt Plaintext-Fallback wenn DoT fehlschlägt — hebt die Sicherheitsgarantie auf. 'yes' lehnt jede unverschlüsselte Antwort ab.";
          beheben = "services.resolved.settings.Resolve.DNSOverTLS = \"yes\"; — kein Wert außer 'yes' ist zulässig.";
          assertion = (config.services.resolved.settings.Resolve.DNSOverTLS or "no") == "yes";
        })
        (asserts.mkAssert {
          code = "DNS-003";
          was = "services.resolved.settings.Resolve.DNS zeigt auf 127.0.0.1 (Blocky/lokaler Forwarder)";
          warum = "Blocky lief früher als lokaler DNS-Forwarder, wurde durch direkte DoT-Verbindung ersetzt (ADR-003). Ein lokaler Forwarder auf 127.0.0.1 würde DoT umgehen.";
          beheben = "DNS auf DoT-Upstream setzen, z.B. '1.1.1.1#one.one.one.one 1.0.0.1#one.one.one.one'. Wert in modules/10-network/1090-host-network.nix → dnsBootstrap.";
          assertion = (config.services.resolved.settings.Resolve.DNS or "") != "127.0.0.1";
        })
        (asserts.mkAssert {
          code = "DNS-004";
          was = "networking.nameservers ist nicht leer";
          warum = "networking.nameservers schreibt /etc/resolv.conf direkt und umgeht resolved komplett — DoT-Garantie entfällt für alle Prozesse die /etc/resolv.conf nutzen.";
          beheben = "networking.nameservers = []; — /etc/resolv.conf wird von resolved verwaltet (127.0.0.53).";
          assertion = config.networking.nameservers == [ ];
        })
        (asserts.mkAssert {
          code = "IPv6-001";
          was = "my.configs.network.ipv6.firewall ist nicht false";
          warum = "q958 ist v4-only Homelab. IPv6-Firewall-Regeln für ungetestetes Protokoll erhöhen Angriffsfläche und Komplexität ohne Nutzen.";
          beheben = "my.configs.network.ipv6.firewall = false; in machines/q958/network.nix setzen.";
          umgehung = "Wenn IPv6 gewünscht: networking.enableIPv6 = true + vollständige nftables ip6-Tabelle schreiben.";
          assertion = config.my.configs.network.ipv6.firewall == false;
        })
        (asserts.mkAssert {
          code = "IPv6-002";
          was = "networking.enableIPv6 ist nicht explizit deaktiviert";
          warum = "Ohne enableIPv6 = false weist der Kernel IPv6-Adressen zu — auch wenn keine Firewall-Regeln dafür existieren. Kernel-Ebene muss IPv6 komplett abschalten.";
          beheben = "networking.enableIPv6 = false; — schaltet IPv6 kernel-seitig ab (sysctl net.ipv6.conf.all.disable_ipv6=1).";
          umgehung = "Wenn IPv6 gewünscht: IPv6-001 lösen, vollständige nftables ip6-Regeln schreiben, dann enableIPv6 = true.";
          assertion = !(config.networking.enableIPv6 or true);
        })
      ];
    }

    # ── CADDY GLOBAL CONFIG & SNIPPETS ────────────────────────────────────────
    # ADR 018: Dual-Log — default-Logger (stdout→journald→CrowdSec) bleibt unverändert.
    # dsgvo_access-Logger abonniert http.log.access (alle vHosts) und schreibt
    # IP-maskierte Logs auf /24 (IPv4) / /48 (IPv6) nach /var/log/caddy/dsgvo.json.
    {
      services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
        servers {
          trusted_proxies static private_ranges 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
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

    {
      # Bedingungslos hier statt in 1096-vpn.nix (privado.enable-abhängig wäre fragil) — ADR-2030.
      systemd.services."systemd-networkd-wait-online".wantedBy = lib.mkForce [ ];

      assertions = [
        {
          assertion = config.systemd.services."systemd-networkd-wait-online".wantedBy == [ ];
          message = "[ADR-2030] systemd-networkd-wait-online.wantedBy ist nicht leer — nixos-rebuild switch würde 2min blockieren. Fix: mkForce [] in modules/10-network/1090-host-network.nix prüfen.";
        }
      ];
    }
  ];
}
