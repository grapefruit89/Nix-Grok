# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures a pure, hardened nftables firewall for the homelab server.
# Completely disables legacy iptables/networking.firewall and implements
# kernel-level SYN-flood protection, ICMP throttling, web-port rate limiting,
# SSH brute force prevention, and automated weekly Geo-IP blocking.

{ config, pkgs, lib, ... }:

let
  cfg = config.my.security.firewall;
  sshPort = config.my.ports.ssh;
  sshPorts = (if config.my.mode == "development" then [ 22 ] else [ sshPort ]) ++ (lib.optional ((config.my.security ? dropbear-rescue) && config.my.security.dropbear-rescue.enable) config.my.security.dropbear-rescue.port);

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.security.firewall = {
    enable = lib.mkEnableOption "Pure, hardened nftables firewall stack (disables legacy iptables)";
    blockedCountries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "cn" "ru" "kp" "ir" "sy" "vn" ];
      description = "List of ISO country codes to block on Layer 3/4.";
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # ── DISABLE LEGACY IPTABLES ───────────────────────────────────────────────
    networking.firewall.enable = false;

    # ── ENABLE NATIVE NFTABLES ────────────────────────────────────────────────
    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet filter {
          # Dynamic set to store blocked Geo-IP ranges (subnets/CIDR require flags interval)
          set geoip_blocked {
            type ipv4_addr
            flags interval
          }

          set crowdsec_blocked_ipv4 {
            type ipv4_addr
            flags interval
          }

          set crowdsec_blocked_ipv6 {
            type ipv6_addr
            flags interval
          }

          # Dynamic set to track and rate limit new SSH connections
          set ssh_meter {
            type ipv4_addr
            flags dynamic, timeout
            timeout 1m
          }

          # Dynamic set to track and rate limit new HTTP/HTTPS connections
          set web_meter {
            type ipv4_addr
            flags dynamic, timeout
            timeout 1m
          }

          chain input {
            type filter hook input priority filter; policy drop;

            # 1. Loopback and trusted VPN interfaces
            iifname lo accept
            iifname tailscale0 accept comment "Accept Tailscale VPN traffic"
            iifname privado accept comment "Accept Privado VPN client traffic"

            # 2. Connection tracking states (allow established/related)
            ct state established,related accept
            ct state invalid drop comment "Drop invalid TCP states"

            # 3. Block fragmented packets
            ip frag-off & 0x3fff != 0 drop comment "Drop fragmented packets"

            # 4. Geo-IP and CrowdSec drop rules (processed early)
            ip saddr @geoip_blocked drop comment "Drop blocked Geo-IP traffic"
            ip saddr @crowdsec_blocked_ipv4 drop comment "Drop CrowdSec banned IPv4"
            ip6 saddr @crowdsec_blocked_ipv6 drop comment "Drop CrowdSec banned IPv6"

            # 5. ICMP (Ping) throttling and safety rules
            ip protocol icmp icmp type echo-request limit rate over 10/second drop
            ip protocol icmp icmp type echo-request accept
            ip protocol icmp icmp type { redirect, router-advertisement } drop
            ip protocol icmp accept comment "Accept other safe ICMP types"

            # 6. TCP SYN DDoS protection (SYN Flood limiting)
            tcp flags & (syn|rst|ack) == syn limit rate over 20/second burst 40 packets drop comment "SYN-Flood protection"

            # 7. Tailscale UDP handshake port acceptance
            udp dport ${toString config.my.services.tailscale.port} accept comment "Allow Tailscale UDP handshake"

            # 8. HTTP/HTTPS rate-limiting and access (Ports 80 & 443)
            tcp dport { 80, 443 } ct state new update @web_meter { ip saddr limit rate over 100/minute } drop
            tcp dport { 80, 443 } accept

            # 9. SSH rate-limiting and access
            tcp dport { ${lib.concatStringsSep ", " (map toString sshPorts)} } ct state new update @ssh_meter { ip saddr limit rate over 10/minute } drop
            tcp dport { ${lib.concatStringsSep ", " (map toString sshPorts)} } accept

            # 10. Log all other dropped packets (rate limited)
            limit rate 5/second log prefix "nftables-dropped: "
          }

          chain forward {
            type filter hook forward priority filter; policy drop;
            iifname "tailscale0" accept comment "Allow Tailscale subnet routing (inbound)"
            oifname "tailscale0" accept comment "Allow Tailscale subnet routing (outbound)"
          }

          chain output {
            type filter hook output priority filter; policy accept;
          }
        }
      '';
    };

    # ── GEO-IP AUTOMATED WEEKLY DOWNLOAD ──────────────────────────────────────
    systemd.services.nftables-geoip-update = {
      description = "Download and update Geo-IP country IP blocks in nftables";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "update-geoip" ''
          set -euo pipefail
          
          TEMP_DIR=$(mktemp -d)
          trap 'rm -rf "$TEMP_DIR"' EXIT

          IP_FILE="$TEMP_DIR/ips.txt"
          touch "$IP_FILE"

          echo "Starting Geo-IP list downloads..."
          for country in ${lib.concatStringsSep " " cfg.blockedCountries}; do
            URL="https://www.ipdeny.com/ipblocks/data/countries/$country.zone"
            echo "Downloading $country IP block list..."
            if ${pkgs.curl}/bin/curl --ssl-reqd -fsS -o "$TEMP_DIR/$country.zone" "$URL"; then
              cat "$TEMP_DIR/$country.zone" >> "$IP_FILE"
            else
              echo "Warning: Failed to fetch zone file for $country. Skipping."
            fi
          done

          # Filter out empty lines or comments
          ${pkgs.gnugrep}/bin/grep -v -E '^\s*(#|$)' "$IP_FILE" > "$TEMP_DIR/clean_ips.txt" || true

          if [ -s "$TEMP_DIR/clean_ips.txt" ]; then
            NFT_FILE="$TEMP_DIR/rules.nft"
            echo "flush set inet filter geoip_blocked" > "$NFT_FILE"
            echo "add element inet filter geoip_blocked {" >> "$NFT_FILE"
            
            # Format elements comma-separated
            paste -sd, "$TEMP_DIR/clean_ips.txt" >> "$NFT_FILE"
            echo "}" >> "$NFT_FILE"

            echo "Atomically updating nftables Geo-IP blocked set..."
            ${pkgs.nftables}/bin/nft -f "$NFT_FILE"
            echo "Geo-IP update finished successfully."
          else
            echo "Error: No Geo-IP subnets downloaded. Keeping existing list."
            exit 1
          fi
        '';

        # Hardening sandboxing properties for systemd service
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      };
    };

    # Timer to trigger Geo-IP update weekly (and 5 mins after boot)
    systemd.timers.nftables-geoip-update = {
      description = "Weekly timer for Geo-IP blocklist update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "7d";
        RandomizedDelaySec = "1h";
      };
    };
  };
}
