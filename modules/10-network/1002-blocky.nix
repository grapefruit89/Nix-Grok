# ---
# schema: "100x=Service-Port (ADR-011 Isomorphie)"
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
  proto = config.my.network.protocol;
in
{
  options.my.services.blocky = {
    enable = lib.mkEnableOption "Blocky DNS resolver with ad-blocking for LAN clients";
    allowlistFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optionaler Host-Pfad für lokale Ads-Allowlist (nicht im Nix-Store).
        Paar mit lib/blocky-allowlist.nix in machines/<host>/network.nix setzen.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optionals (cfg.enable && cfg.allowlistFile != null) [
        {
          assertion = lib.hasPrefix "/" cfg.allowlistFile && !(lib.hasPrefix "/nix/store/" cfg.allowlistFile);
          message = "[BLOCKY] allowlistFile muss absoluter Host-Pfad sein (nicht /nix/store) — lib/blocky-allowlist.nix nutzen.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      services.blocky = {
        enable = true;
        enableConfigCheck = true;
        settings = {
          ports = {
            # Nur LAN-Interface — systemd-resolved belegt 127.0.0.53:53
            dns = "${config.my.configs.server.lanIP}:${toString proto.dns}";
            http = config.my.ports.blocky;
          };

          upstreams.groups.default = map (s: "tcp-tls:${s.hostname}:${toString proto.dot}") dot;

          customDNS = {
            mapping = {
              "${config.my.configs.identity.domain}" = config.my.configs.server.lanIP;
            };
            filterUnmappedTypes = false;
          };

          blocking = {
            denylists.ads = [
              "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
            ];
            allowlists.ads = lib.optionals (cfg.allowlistFile != null) [ cfg.allowlistFile ];
            clientGroupsBlock.default = [ "ads" ];
            loading = {
              refreshPeriod = "24h";
              downloads = {
                attempts = 3;
                cooldown = "2s";
              };
            };
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

      systemd.services.blocky = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        startLimitIntervalSec = lib.mkDefault 0;
        startLimitBurst = lib.mkDefault 0;
        serviceConfig = {
          OOMScoreAdjust = lib.mkDefault (-300);
          Restart = lib.mkDefault "on-failure";
          RestartSec = lib.mkDefault "5s";
          ProtectHome = lib.mkIf (cfg.allowlistFile != null) (lib.mkForce "read-only");
        };
      };
    })
  ];
}
