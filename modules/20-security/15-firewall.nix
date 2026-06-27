# ---
# meta:
#   layer: 3
#   role: module
#   purpose: nftables L4 — checkRuleset, WAN-Härtung, skuid, CrowdSec/Fail2ban
#   docs:
#     - docs/adr/008-nftables-l4-hardening.md
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
}: let
  cfg = config.my.security.firewall;
  blockedCountryList = lib.concatStringsSep " " cfg.blockedCountries;
  ruleset = import ../../lib/nftables-rules.nix {inherit lib config;};
in {
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

    blockedCountries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cn"
        "ru"
        "kp"
        "ir"
        "sy"
        "vn"
      ];
      description = "ISO-Ländercodes für ipdeny.com → geoip_blocked Set (Blocklist).";
    };

    allowLanDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "UDP/TCP 53 von LAN an Blocky erlauben (DHCP DNS → q958).";
    };

    webRateLimit = lib.mkOption {
      type = lib.types.str;
      default = "100/minute";
      description = "Neue HTTP/HTTPS-Verbindungen pro Quell-IP (WAN).";
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "IPv6-Input-Regeln (CrowdSec v6). false wenn LAN nur v4 (Tailscale bleibt über iifname tailscale0).";
    };

    tailscaleNotrack = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "raw-Table NOTRACK für tailscale0 — weniger conntrack-CPU.";
    };

    skuidSegmentation = {
      enable = lib.mkEnableOption "meta skuid Micro-Segmentation (UID-Registry, Stufe 8+)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.enable = false;

    networking.nftables = {
      enable = true;
      checkRuleset = true;
      inherit ruleset;
    };

    # Sicherheits-Assertions für Firewall-Konfiguration
    assertions = [
      {
        assertion = cfg.lanCidrs != [];
        message = "FIREWALL: lanCidrs darf nicht leer sein — mindestens ein vertrauenswürdiges Netz definieren.";
      }
      {
        assertion = cfg.blockedCountries != [];
        message = "FIREWALL: blockedCountries sollte nicht leer sein — Geo-Blocking aktivieren.";
      }
      {
        assertion = cfg.webRateLimit != "";
        message = "FIREWALL: webRateLimit darf nicht leer sein.";
      }
      {
        assertion = !(cfg.skuidSegmentation.enable && !config.my.users.registry ? prowlarr);
        message = "FIREWALL: skuidSegmentation benötigt UID-Registry (prowlarr/sabnzbd UIDs).";
      }
    ];

    systemd.services.nftables-geoip-update = {
      description = "Geo-IP blocklist → nftables set geoip_blocked";
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "update-geoip" ''
          set -euo pipefail
          TEMP_DIR=$(mktemp -d)
          trap 'rm -rf "$TEMP_DIR"' EXIT
          IP_FILE="$TEMP_DIR/ips.txt"
          touch "$IP_FILE"
          for country in ${blockedCountryList}; do
            URL="https://www.ipdeny.com/ipblocks/data/countries/$country.zone"
            echo "Fetching $country..."
            ${pkgs.curl}/bin/curl --ssl-reqd -fsS -o "$TEMP_DIR/$country.zone" "$URL" \
              && cat "$TEMP_DIR/$country.zone" >> "$IP_FILE" \
              || echo "WARN: skip $country"
          done
          ${pkgs.gnugrep}/bin/grep -v -E '^\s*(#|$)' "$IP_FILE" > "$TEMP_DIR/clean_ips.txt" || true
          if [ ! -s "$TEMP_DIR/clean_ips.txt" ]; then
            echo "ERROR: no subnets fetched"
            exit 1
          fi
          NFT_FILE="$TEMP_DIR/rules.nft"
          echo "flush set inet filter geoip_blocked" > "$NFT_FILE"
          echo "add element inet filter geoip_blocked {" >> "$NFT_FILE"
          paste -sd, "$TEMP_DIR/clean_ips.txt" >> "$NFT_FILE"
          echo "}" >> "$NFT_FILE"
          ${pkgs.nftables}/bin/nft -f "$NFT_FILE"
          echo "geoip_blocked updated ($(wc -l < "$TEMP_DIR/clean_ips.txt") prefixes)"
        '';
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        CapabilityBoundingSet = ["CAP_NET_ADMIN"];
      };
    };

    systemd.timers.nftables-geoip-update = {
      description = "Weekly Geo-IP refresh";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "7d";
        RandomizedDelaySec = "1h";
      };
    };
  };
}
