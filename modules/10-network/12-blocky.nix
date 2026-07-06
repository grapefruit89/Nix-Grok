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
          dns = 53;
          http = config.my.ports.blocky;
        };

        upstreams.groups.default = map (s: "tcp-tls:${s.ip}:853") dot;

        bootstrapDns = [
          "1.1.1.1"
          "9.9.9.9"
        ];

        customDNS = {
          mapping = {
            "${config.my.configs.identity.domain}" = config.my.configs.server.lanIP;
          };
          filterUnmappedTypes = false;
        };

        blocking = {
          blackLists.ads = [
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
            "https://dbl.oisd.nl/"
          ];
          whiteLists.ads = [ "/home/moritz/blocky-allowlist.txt" ];
          clientGroupsBlock.default = [ "ads" ];
          refreshPeriod = "24h";
          downloadAttempts = 3;
          downloadCooldown = "2s";
          failOnDnsError = false;
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

    # Allowlist liegt in /home/moritz — world-readable (644) via tmpfiles
    systemd.tmpfiles.rules = [
      "f /home/moritz/blocky-allowlist.txt 0644 moritz users -"
    ];

    systemd.services.blocky = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        OOMScoreAdjust = lib.mkDefault (-300);
      };
    };
  };
}
