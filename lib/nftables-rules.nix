# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: nftables ruleset Generator — WAN-Härtung, skuid, portscan
#   docs:
#     - docs/adr/008-nftables-l4-hardening.md
#     - docs/guides/GUIDE-nftables-hardening.md
#   tags:
#     - nftables
#     - firewall
# ---
{ lib, config }:

let
  cfg = config.my.security.firewall;
  ports = config.my.ports;
  uids = config.my.users.registry;
  lanCidrList = lib.concatStringsSep ", " cfg.lanCidrs;
  lanIf = cfg.lanInterface;
  hasLanIf = lanIf != "";
  sshPort = config.my.ports.ssh;
  sshPorts =
    (if config.my.mode == "development" then [ 22 ] else [ sshPort ])
    ++ lib.optional (
      (config.my.security ? dropbear-rescue) && config.my.security.dropbear-rescue.enable
    ) config.my.security.dropbear-rescue.port;
  sshPortList = lib.concatStringsSep ", " (map toString sshPorts);
  tailscalePort = toString config.my.services.tailscale.port;
  wanIf = cfg.wanInterface;
  hasWanIf = wanIf != "";

  arrPorts = lib.concatStringsSep ", " [
    (toString ports.sonarr)
    (toString ports.radarr)
    (toString ports.readarr)
  ];

  skuidArrGuard =
    if cfg.skuidSegmentation.enable then
      ''
        tcp dport { ${arrPorts} } ct state new ip saddr != { 127.0.0.0/8, ${lanCidrList}, 100.64.0.0/10 } drop comment "arr LAN/Tailscale only"
      ''
    else
      "";

  skuidUsenetGuard =
    if cfg.skuidSegmentation.enable then
      ''
        meta skuid { ${toString uids.prowlarr}, ${toString uids.sabnzbd} } oifname != "lo" oifname != "tailscale0" oifname != "privado" oifname != "veth-usenet" oifname != "veth-usenet-br" oifname != "usenet-br" ip daddr != { ${lanCidrList}, 192.168.15.0/24 } drop comment "usenet UIDs egress"
      ''
    else
      "";

  dbInputGuard =
    if cfg.skuidSegmentation.enable then
      ''
        tcp dport { 5432, 6379 } ip saddr != 127.0.0.0/8 drop comment "DB sockets localhost only"
      ''
    else
      "";

  wanBogon =
    if hasWanIf then
      ''
        iifname "${wanIf}" ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16 } drop comment "WAN bogon spoof"
      ''
    else
      ''
        ip saddr { 127.0.0.0/8, 169.254.0.0/16 } drop comment "bogon loopback/link-local"
      '';

  ipv6Crowdsec =
    if cfg.ipv6 then
      ''
        ip6 saddr @crowdsec_blocked_ipv6 drop comment "CrowdSec IPv6"
      ''
    else
      "";

  ipv6LanDrop =
    if (!cfg.ipv6 && config.my.configs.network.ipv6.disableOnInterfaces != [ ]) then
      ''
        iifname { ${
          lib.concatStringsSep ", " (map (i: "\"${i}\"") config.my.configs.network.ipv6.disableOnInterfaces)
        } } meta nfproto ipv6 drop comment "IPv6 off on LAN ifaces"
      ''
    else
      "";

  rawNotrack =
    if cfg.tailscaleNotrack then
      ''
        table inet raw {
          chain prerouting {
            type filter hook prerouting priority -300; policy accept;
            iifname "tailscale0" notrack comment "Tailscale NOTRACK"
          }
        }
      ''
    else
      "";

in
lib.concatStringsSep "\n" [
  rawNotrack
  ''
    table inet filter {
      set geoip_blocked {
        type ipv4_addr
        flags interval
      }

      set crowdsec_blocked_ipv4 {
        type ipv4_addr
        flags interval
      }

      set f2b_blocked_ipv4 {
        type ipv4_addr
        flags timeout
        timeout 1h
      }

      ${lib.optionalString cfg.ipv6 ''
        set crowdsec_blocked_ipv6 {
          type ipv6_addr
          flags interval
        }
      ''}

      set portscan {
        type ipv4_addr
        flags dynamic, timeout
        timeout 24h
      }

      set ssh_meter {
        type ipv4_addr
        flags dynamic, timeout
        timeout 1m
      }

      set web_meter {
        type ipv4_addr
        flags dynamic, timeout
        timeout 1m
      }

      chain input {
        type filter hook input priority filter; policy drop;
        jump in_trusted
        jump in_lan
        jump in_wan
        limit rate 5/second log prefix "nftables-dropped: "
      }

      chain in_trusted {
        iifname "lo" accept
        iifname "tailscale0" accept comment "Tailscale"
        iifname "privado" accept comment "Privado WG egress"
        ct state established,related accept
        ct state invalid drop comment "Invalid TCP state"
        ip frag-off & 0x3fff != 0 drop comment "Fragments"
        tcp flags & (fin|syn|rst|psh|ack) == 0 drop comment "NULL scan"
        tcp flags & (fin|syn|rst|psh|ack) == fin drop comment "FIN scan"
        tcp flags & (fin|psh|urg) == (fin|psh|urg) drop comment "XMAS scan"
        ip saddr @geoip_blocked drop comment "Geo blocklist"
        ip saddr @crowdsec_blocked_ipv4 drop comment "CrowdSec IPv4"
        ip saddr @f2b_blocked_ipv4 drop comment "Fail2ban"
        ${ipv6Crowdsec}
        ${ipv6LanDrop}
        return
      }

      chain in_lan {
        ${lib.optionalString hasLanIf ''
          iifname "${lanIf}" ip saddr { ${lanCidrList} } accept comment "LAN trusted"
        ''}
        ${lib.optionalString (!hasLanIf) ''
          ip saddr { ${lanCidrList} } accept comment "LAN trusted"
        ''}
        return
      }

      chain in_wan {
        ${wanBogon}
        icmp type echo-request limit rate over 10/second drop
        icmp type echo-request accept
        icmp type { redirect, router-advertisement } drop
        ip protocol icmp accept
        tcp flags & (syn|ack) == syn ct state new add @portscan { ip saddr limit rate 30/minute burst 5 packets } drop comment "Portscan"
        tcp flags & (syn|ack) == syn limit rate over 20/second burst 40 packets drop comment "SYN flood"
        udp dport ${tailscalePort} accept comment "Tailscale UDP"
        ip protocol udp ct state new limit rate over 50/second burst 100 packets drop comment "UDP flood"
        ${skuidArrGuard}
        ${dbInputGuard}
        tcp dport { 80, 443 } ct state new update @web_meter { ip saddr limit rate over ${cfg.webRateLimit} } drop
        tcp dport { 80, 443 } ct state new limit rate over 30/second burst 60 packets drop comment "HTTP conn flood"
        tcp dport { 80, 443 } accept
        tcp dport { ${sshPortList} } ct state new update @ssh_meter { ip saddr limit rate over 10/minute } drop
        tcp dport { ${sshPortList} } ct state new ct count over 3 drop comment "SSH parallel"
        tcp dport { ${sshPortList} } accept
        return
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        iifname "tailscale0" accept
        oifname "tailscale0" accept
      }

      chain output {
        type filter hook output priority filter; policy accept;
        ${skuidUsenetGuard}
      }
    }
  ''
]
