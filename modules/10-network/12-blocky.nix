# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Blocky DNS — ad-blocking, split-horizon, DoT-Upstreams für LAN-Clients
#   services:
#     - blocky
#   tags:
#     - dns
#     - ad-blocking
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.blocky;
  dot = config.my.configs.network.dnsBootstrap;
in
{
  options.my.services.blocky = {
    enable = lib.mkEnableOption "Blocky DNS resolver with ad-blocking for LAN clients";
  };

  config = lib.mkIf cfg.enable {
    services.blocky = {
      enable = true;
      settings = {
        ports = {
          # Nur LAN-Interface — systemd-resolved belegt 127.0.0.53:53
          dns = "${config.my.configs.server.lanIP}:53";
          http = config.my.ports.blocky;
        };

        upstreams.groups.default = map (s: "tcp-tls:${s.ip}:853") dot;

        # Kein bootstrapDns — Upstreams sind IPs, kein Hostname-Lookup nötig.
        # Go's HTTP-Client nutzt den OS-Resolver (systemd-resolved) mit Happy Eyeballs,
        # der auf IPv4 zurückfällt wenn IPv6 deaktiviert ist.

        customDNS = {
          mapping = {
            "${config.my.configs.identity.domain}" = config.my.configs.server.lanIP;
          };
          filterUnmappedTypes = false;
        };

        blocking = {
          blackLists.ads = [
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
          ];
          whiteLists.ads = [ "/home/moritz/blocky-allowlist.txt" ];
          clientGroupsBlock.default = [ "ads" ];
          refreshPeriod = "24h";
          downloadAttempts = 3;
          downloadCooldown = "2s";
        };

        log = {
          level = "info";
          format = "text";
        };

        prometheus = {
          enable = true;
          path = "/metrics";
        };
      };
    };

    # Allowlist in /home/moritz — ProtectHome auf read-only damit der Service lesen kann
    systemd.tmpfiles.rules = [
      "f /home/moritz/blocky-allowlist.txt 0644 moritz users -"
    ];

    systemd.services.blocky = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        OOMScoreAdjust = lib.mkDefault (-300);
        # ProtectHome=true (Default) würde /home verstecken — read-only erlaubt Lesen
        ProtectHome = lib.mkForce "read-only";
      };
    };
  };
}
