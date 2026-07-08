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
        Imperativ freigeschaltete Länder zusätzlich zu DE (ISO-2: "at", "lt").
        DE ist immer hardcoded im Service — kein Eintrag nötig.
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
        # Kontrollierter Escape-Hatch: lädt bei Boot (30s) + wöchentlich GeoIP-Whitelists von
        # ipdeny.com und befüllt nftables-Set geoip_allowed via `nft -f`. DE immer, AT/LT optional.
        # Ohne diesen Service bleibt geoip_allowed leer → alles außer RFC1918 wird geblockt.
        description = "Boot+Weekly GeoIP-Whitelist-Update (ipdeny.com → nftables geoip_allowed). DE immer, AT/LT via allowedCountries.";
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

    systemd.services.nftables-geoip-update = lib.mkIf cfg.geoipAutoUpdate.enable {
      description = "Geo-IP whitelist → nftables set geoip_allowed (DE immer + optional AT/LT)";
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "update-geoip-allowed" ''
          set -euo pipefail
          TEMP_DIR=$(mktemp -d)
          trap 'rm -rf "$TEMP_DIR"' EXIT
          IP_FILE="$TEMP_DIR/ips.txt"
          touch "$IP_FILE"
          # DE ist immer Pflicht (deklarativ hardcoded) — AT/LT via allowedCountries optional
          for country in de ${allowedCountryList}; do
            URL="https://www.ipdeny.com/ipblocks/data/aggregated/$country-aggregated.zone"
            echo "geoip-whitelist: lade $country..."
            ${pkgs.curl}/bin/curl --ssl-reqd -fsS -o "$TEMP_DIR/$country.zone" "$URL" \
              && cat "$TEMP_DIR/$country.zone" >> "$IP_FILE" \
              || echo "WARN: $country übersprungen"
          done
          ${pkgs.gnugrep}/bin/grep -v -E '^\s*(#|$)' "$IP_FILE" > "$TEMP_DIR/clean_ips.txt" || true
          if [ ! -s "$TEMP_DIR/clean_ips.txt" ]; then
            echo "ERROR: keine Prefixes geladen — DE-Zone nicht erreichbar"
            exit 1
          fi
          NFT_FILE="$TEMP_DIR/rules.nft"
          echo "flush set inet filter geoip_allowed" > "$NFT_FILE"
          echo "add element inet filter geoip_allowed {" >> "$NFT_FILE"
          paste -sd, "$TEMP_DIR/clean_ips.txt" >> "$NFT_FILE"
          echo "}" >> "$NFT_FILE"
          ${pkgs.nftables}/bin/nft -f "$NFT_FILE"
          echo "geoip_allowed aktualisiert ($(wc -l < "$TEMP_DIR/clean_ips.txt") Prefixes)"
        '';
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      };
    };

    systemd.timers.nftables-geoip-update = lib.mkIf cfg.geoipAutoUpdate.enable {
      description = "Monatlicher GeoIP-Whitelist-Refresh (DE+AT+LT → geoip_allowed)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30d";
        RandomizedDelaySec = "6h";
      };
    };
  };
}
