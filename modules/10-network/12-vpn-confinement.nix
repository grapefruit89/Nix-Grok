# ---
# meta:
#   id: NIXH-10-VPN-001
#   layer: 3
#   role: module
#   purpose: VPN Network-Namespaces für Usenet (veth-Bridge, Kill-Switch, Healthcheck)
#   docs:
#     - docs/adr/009-vpn-leak-check.md
#   tags:
#     - vpn
#     - netns
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.vpn-confinement;
  ports = config.my.ports;
  nsNames = lib.attrNames cfg.namespaces;
  primaryNs = if nsNames != [ ] then lib.head nsNames else "";

  servicePorts = {
    inherit (ports) sabnzbd;
    inherit (ports) prowlarr;
  };

  mkNetnsUnit =
    name: nsCfg:
    let
      wgIf = "wg-${name}";
      vethHost = "veth-${name}-br";
      vethNs = "veth-${name}";
      bridge = "${name}-br";
      openPorts = lib.filter (p: p != null) (map (s: servicePorts.${s} or null) nsCfg.services);
      openPortRules = lib.concatMapStrings (port: ''
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch input iifname "${vethNs}" tcp dport ${toString port} accept
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch input iifname "${vethNs}" udp dport ${toString port} accept
      '') openPorts;
      dnsLines = lib.concatMapStrings (dns: "nameserver ${dns}\n") nsCfg.dns;
    in
    {
      description = "VPN network namespace ${name}";
      before = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        iproute2
        wireguard-tools
        nftables
        curl
        bind.dnsutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        ${pkgs.iproute2}/bin/ip netns add ${name} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip link set lo up

        ${pkgs.iproute2}/bin/ip link del ${wgIf} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link add ${wgIf} type wireguard
        ${pkgs.iproute2}/bin/ip link set ${wgIf} netns ${name}
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.wireguard-tools}/bin/wg setconf ${wgIf} ${nsCfg.wgConf}
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip link set ${wgIf} up
        ${lib.optionalString (nsCfg.address != "") ''
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip addr add ${nsCfg.address} dev ${wgIf}
        ''}
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip route add default dev ${wgIf}

        ${lib.optionalString (dnsLines != "") ''
            mkdir -p /etc/netns/${name}
            cat > /etc/netns/${name}/resolv.conf <<'EOF'
          ${dnsLines}EOF
        ''}

        ${lib.optionalString nsCfg.killSwitch ''
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add table inet killswitch
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add chain inet killswitch input \
            '{ type filter hook input priority 0; policy drop; }'
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add chain inet killswitch output \
            '{ type filter hook output priority 0; policy drop; }'
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch input iifname lo accept
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch input iifname "${vethNs}" accept
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch input ct state established,related accept
          ${openPortRules}
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch output oifname { "${wgIf}", "lo", "${vethNs}" } accept
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.nftables}/bin/nft add rule inet killswitch output ct state established,related accept
        ''}

        ${pkgs.iproute2}/bin/ip link add ${bridge} type bridge 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip addr flush dev ${bridge} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip addr add ${nsCfg.bridgeAddress}/24 dev ${bridge}
        ${pkgs.iproute2}/bin/ip link set dev ${bridge} up

        ${pkgs.iproute2}/bin/ip link del ${vethHost} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link add ${vethHost} type veth peer name ${vethNs} netns ${name}
        ${pkgs.iproute2}/bin/ip link set ${vethHost} master ${bridge}
        ${pkgs.iproute2}/bin/ip link set dev ${vethHost} up
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip addr add ${nsCfg.namespaceAddress}/24 dev ${vethNs}
        ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip link set dev ${vethNs} up

        ${lib.concatMapStrings (cidr: ''
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ip route add ${cidr} via ${nsCfg.bridgeAddress} dev ${vethNs} 2>/dev/null || true
        '') nsCfg.accessibleFrom}

        ${lib.optionalString nsCfg.healthcheck.enable ''
          if [ -n "${nsCfg.healthcheck.endpoint}" ]; then
            echo "Checking WireGuard endpoint reachability..."
            ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.iproute2}/bin/ping -c 1 -W 5 "${nsCfg.healthcheck.endpoint}" >/dev/null
          fi
          echo "Checking VPN egress..."
          ${pkgs.iproute2}/bin/ip netns exec ${name} ${pkgs.curl}/bin/curl -fsS --max-time 15 https://ipinfo.io/ip >/dev/null
        ''}
      '';
      preStop = ''
        ${pkgs.iproute2}/bin/ip link del ${vethHost} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ${bridge} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns del ${name} 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link del ${wgIf} 2>/dev/null || true
        rm -rf /etc/netns/${name} 2>/dev/null || true
      '';
    };

  netnsServices = lib.mapAttrs mkNetnsUnit cfg.namespaces;

  confinedAttrs = name: {
    bindsTo = [ "${name}.service" ];
    after = [ "${name}.service" ];
    serviceConfig.NetworkNamespacePath = "/var/run/netns/${name}";
  };

  serviceBinds = lib.foldl' (
    acc: nsName:
    let
      ns = cfg.namespaces.${nsName};
    in
    acc // lib.genAttrs ns.services (_: confinedAttrs nsName)
  ) { } (lib.attrNames cfg.namespaces);

  leakCheckScript = pkgs.writeShellScript "vpn-leak-check" ''
    set -euo pipefail
    ns="${primaryNs}"
    if [ -z "$ns" ]; then
      echo "vpn-leak-check: skip (no VPN namespaces configured)"
      exit 0
    fi
    HOST_IP=$(${pkgs.curl}/bin/curl -fsS --max-time 15 https://ipinfo.io/ip || echo "")
    NS_IP=$(${pkgs.iproute2}/bin/ip netns exec "$ns" ${pkgs.curl}/bin/curl -fsS --max-time 15 https://ipinfo.io/ip || echo "")
    if [ -z "$HOST_IP" ] || [ -z "$NS_IP" ]; then
      echo "vpn-leak-check: skip (egress probe failed)"
      exit 0
    fi
    if [ "$HOST_IP" = "$NS_IP" ]; then
      echo "vpn-leak-check: LEAK — netns $ns egress equals host ($HOST_IP)"
      ${pkgs.systemd}/bin/systemctl stop sabnzbd.service prowlarr.service 2>/dev/null || true
      exit 1
    fi
    echo "vpn-leak-check: OK host=$HOST_IP ns=$NS_IP"
  '';

  vpnTestScript = pkgs.writeShellApplication {
    name = "vpn-netns-test";
    runtimeInputs = with pkgs; [
      iproute2
      curl
      bind.dnsutils
      coreutils
    ];
    text = ''
      set -euo pipefail
      ns="${primaryNs}"
      if [ -z "$ns" ]; then
        echo "vpn-netns-test: no VPN namespaces configured"
        exit 1
      fi
      echo "=== DNS (netns) ==="
      ${pkgs.iproute2}/bin/ip netns exec "$ns" cat /etc/netns/"$ns"/resolv.conf 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip netns exec "$ns" ${pkgs.bind.dnsutils}/bin/dig +short google.com @''$(
        grep -m1 '^nameserver' /etc/netns/"$ns"/resolv.conf 2>/dev/null | awk '{print $2}'
      ) || true
      echo "=== Egress IP ==="
      ${pkgs.iproute2}/bin/ip netns exec "$ns" ${pkgs.curl}/bin/curl -fsS --max-time 15 https://ipinfo.io
      echo ""
      echo "VPN netns test OK"
    '';
  };
in
{
  options.my.services.vpn-confinement = {
    enable = lib.mkEnableOption "VPN network namespaces (stärker als RestrictNetworkInterfaces)";

    vpnTest = {
      enable = lib.mkEnableOption "Oneshot VPN leak/egress test (manuell: systemctl start vpn-netns-test)";
    };

    leakCheck = {
      enable = lib.mkEnableOption "Periodic VPN leak detection — stop usenet services on host-IP egress match";
      interval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/15";
        description = "systemd OnCalendar timer for leak checks.";
      };
    };

    namespaces = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            wgConf = lib.mkOption {
              type = lib.types.path;
              description = "WireGuard setconf file (ohne Address-Zeile).";
            };
            address = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "WireGuard interface address (z. B. 100.64.8.117/32).";
            };
            dns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "DNS resolver(s) inside the namespace (/etc/netns/<name>/resolv.conf).";
            };
            namespaceAddress = lib.mkOption {
              type = lib.types.str;
              default = "192.168.15.1";
              description = "veth-IP im VPN-NetNS — von Host/Caddy/*arr erreichbar.";
            };
            bridgeAddress = lib.mkOption {
              type = lib.types.str;
              default = "192.168.15.5";
              description = "Bridge-IP auf dem Host — von VPN-NetNS zu Host-*arr erreichbar.";
            };
            accessibleFrom = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "192.168.15.0/24"
              ];
              description = "Routen vom VPN-NetNS zum Host (für Sonarr/Radarr API aus Prowlarr).";
            };
            killSwitch = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            healthcheck = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Nach NetNS-Setup Endpoint-Ping und Egress-Curl.";
              };
              endpoint = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "WireGuard-Endpoint-IP für Ping (leer = überspringen).";
              };
            };
            services = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "systemd unit names die in diesem NS laufen.";
            };
          };
        }
      );
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;

    systemd.services = lib.mkMerge (
      [
        netnsServices
        serviceBinds
      ]
      ++ lib.optional (cfg.leakCheck.enable && primaryNs != "") {
        vpn-leak-check = {
          description = "VPN namespace egress leak check";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = leakCheckScript;
          };
        };
      }
      ++ lib.optional (cfg.vpnTest.enable && primaryNs != "") {
        vpn-netns-test = {
          description = "VPN namespace egress and DNS test";
          after = lib.map (n: "${n}.service") nsNames;
          bindsTo = lib.map (n: "${n}.service") nsNames;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "${vpnTestScript}/bin/vpn-netns-test";
        };
      }
    );

    systemd.timers = lib.mkIf (cfg.leakCheck.enable && primaryNs != "") {
      vpn-leak-check = {
        description = "Periodic VPN leak check";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.leakCheck.interval;
          RandomizedDelaySec = "2m";
          Persistent = true;
        };
      };
    };
  };
}
