# ---
# meta:
#   layer: 3
#   role: module
#   purpose: nftables L4 — checkRuleset, WAN-Härtung, skuid, CrowdSec/Fail2ban
#   docs:
#     - docs/adr/2008-nftables-l4-hardening.md
#     - docs/guides/GUIDE-nftables-hardening.md
#   lib:
#     - lib/nftables-rules.nix
#   services:
#     - nftables
#   tags:
#     - firewall
#     - nftables
# ---
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.security.firewall;
  asserts = import ../../lib/assertions.nix { inherit lib; };
  allowedCountryList = lib.concatStringsSep " " cfg.allowedCountries;
  ruleset = import ../../lib/nftables-rules.nix { inherit lib config; };
  # DE-Zone: zur Buildzeit aus vendortem File generiert — kein Netz nötig
  geoipDeNft = pkgs.runCommand "geoip-de.nft" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
    {
      printf 'flush set inet filter geoip_allowed\nadd element inet filter geoip_allowed {\n'
      grep -vE '^\s*(#|$)' ${./geoip-de.zone} | paste -sd,
      printf '\n}\n'
    } > $out
  '';
in
{
  options.my.security.firewall = {
    enable = lib.mkEnableOption "nftables L4 firewall (ersetzt networking.firewall)";

    lanCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
      description = "Vertrauenswürdige LAN-CIDRs — vor Geo-Block akzeptiert.";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Physisches LAN-Interface (z. B. eno1). Leer = Single-NIC ohne iifname-Check.";
    };

    wanInterface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "WAN-Interface für Bogon-Drop. Leer = Homelab Single-NIC (nur Loopback/Link-Local).";
    };

    allowedCountries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Optional: zusätzliche Länder zur Laufzeit nachladen (ISO-2: "at", "lt").
        DE ist immer deklarativ im Store — kein Eintrag nötig.
        AT + LT hier eintragen wenn Netbird/Reisen abgedeckt sein sollen.
      '';
    };

    allowLanDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "UDP/TCP 53 von LAN an lokalen DNS-Server erlauben.";
    };

    blockCleartextDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Port 53 (unverschlüsseltes DNS) outbound sperren — nur DoT via systemd-resolved erlaubt. Loopback (127.0.0.0/8) bleibt offen für Blocky.";
    };

    webRateLimit = lib.mkOption {
      type = lib.types.str;
      default = "100/minute";
      description = "Neue HTTP/HTTPS-Verbindungen pro Quell-IP (WAN).";
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "IPv6-Input-Regeln (CrowdSec v6). false wenn LAN nur v4 (Netbird bleibt über iifname wt0).";
    };

    netbirdNotrack = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "raw-Table NOTRACK für wt0 (Netbird) — weniger conntrack-CPU.";
    };

    skuidSegmentation = {
      enable = lib.mkEnableOption "meta skuid Micro-Segmentation (UID-Registry, Stufe 8+)";
    };

    geoipAutoUpdate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        # Kontrolliert optionalen Runtime-Fetch für AT/LT via ipdeny.com.
        # DE ist immer geladen (nftables-geoip-de.service, Nix-Store, kein Netz).
        # false = nur DE aktiv, AT/LT-Timer deaktiviert.
        description = "AT/LT GeoIP-Refresh via ipdeny.com (Boot+Monatlich). DE ist unabhängig immer geladen.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.enable = false;

    networking.nftables = {
      enable = true;
      checkRuleset = true;
      inherit ruleset;
    };

    assertions = [
      (asserts.mkAssert {
        code = "FIREWALL-001";
        was = "my.security.firewall.lanCidrs ist leer — kein vertrauenswürdiges Netz definiert";
        warum = "LAN-CIDRs definieren in nftables welche IPs als 'intern' gelten. Ohne sie haben LAN-Only-Dienste (Grafana, Home Assistant, Proxmox) keine Zugriffsbeschränkung auf private IPs.";
        beheben = "my.security.firewall.lanCidrs = [\"192.168.x.0/24\"]; — eigenes LAN-Subnetz eintragen. Mehrere CIDRs (LAN + IoT-VLAN) als Liste möglich.";
        assertion = cfg.lanCidrs != [ ];
      })
      (asserts.mkAssert {
        code = "FIREWALL-002";
        was = "my.security.firewall.webRateLimit ist leer — kein Rate-Limit für eingehende HTTP/S-Verbindungen";
        warum = "Ohne Rate-Limit sind Port 443/80 unbegrenzt offen — auch für Connection-Floods. Das Rate-Limit ist die erste Verteidigungslinie vor Caddy/CrowdSec.";
        beheben = "my.security.firewall.webRateLimit = \"40/minute\"; — Wert je nach erwartetem Traffic anpassen.";
        assertion = cfg.webRateLimit != "";
      })
      (asserts.mkAssert {
        code = "FIREWALL-003";
        was = "my.security.firewall.skuidSegmentation ist aktiv, aber 'prowlarr' fehlt in my.users.registry";
        warum = "Netzwerk-Segmentierung nach UID erfordert vollständige UID-Registry aller Media-Dienste. Fehlt prowlarr, gilt die nftables skuid-Regel nicht → Segmentierung ist wirkungslos.";
        beheben = "my.users.registry.prowlarr = { uid = <uid>; gid = <gid>; }; ergänzen — oder skuidSegmentation deaktivieren.";
        umgehung = "my.security.firewall.skuidSegmentation.enable = false; bis Registry vollständig ist.";
        assertion = !(cfg.skuidSegmentation.enable && !config.my.users.registry ? prowlarr);
      })
    ];

    # DE-Zone immer geladen: aus dem Nix-Store, kein Netz, kein Timer.
    # partOf nftables.service → bei jedem Firewall-Reload automatisch neu geladen.
    systemd.services.nftables-geoip-de = {
      description = "GeoIP DE-Basis aus Nix-Store laden (kein Netz)";
      after = [ "nftables.service" ];
      requires = [ "nftables.service" ];
      partOf = [ "nftables.service" ];
      wantedBy = [ "nftables.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nftables}/bin/nft -f ${geoipDeNft}";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
      };
    };

    # AT/LT optional: nur wenn allowedCountries gesetzt + geoipAutoUpdate aktiv.
    # Fügt IPs per `add element` hinzu — DE-Basis bleibt erhalten.
    systemd.services.nftables-geoip-update =
      lib.mkIf (cfg.geoipAutoUpdate.enable && cfg.allowedCountries != [ ])
        {
          description = "GeoIP optionale Länder nachladen (${allowedCountryList} → nftables geoip_allowed)";
          after = [
            "network-online.target"
            "nftables-geoip-de.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "nftables-geoip-de.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "update-geoip-optional" ''
              set -euo pipefail
              TEMP_DIR=$(mktemp -d)
              trap 'rm -rf "$TEMP_DIR"' EXIT
              NFT_FILE="$TEMP_DIR/optional.nft"
              : > "$NFT_FILE"
              for country in ${allowedCountryList}; do
                URL="https://www.ipdeny.com/ipblocks/data/aggregated/$country-aggregated.zone"
                echo "geoip: lade optional $country..."
                if ${pkgs.curl}/bin/curl --ssl-reqd -fsS -o "$TEMP_DIR/$country.zone" "$URL"; then
                  {
                    printf 'add element inet filter geoip_allowed {\n'
                    ${pkgs.gnugrep}/bin/grep -vE '^\s*(#|$)' "$TEMP_DIR/$country.zone" | paste -sd,
                    printf '\n}\n'
                  } >> "$NFT_FILE"
                else
                  echo "WARN: $country übersprungen"
                fi
              done
              if [ -s "$NFT_FILE" ]; then
                ${pkgs.nftables}/bin/nft -f "$NFT_FILE"
                echo "geoip_allowed: optionale Länder geladen"
              fi
            '';
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
          };
        };

    systemd.timers.nftables-geoip-update =
      lib.mkIf (cfg.geoipAutoUpdate.enable && cfg.allowedCountries != [ ])
        {
          description = "Monatlicher GeoIP-Refresh für optionale Länder (${allowedCountryList})";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitActiveSec = "30d";
            RandomizedDelaySec = "6h";
          };
        };
  };
}
