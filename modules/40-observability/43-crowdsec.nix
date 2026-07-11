# ---
# meta:
#   id: NIXH-43-MOD-001
#   layer: 3
#   role: module
#   purpose: CrowdSec Security-Engine + nftables Firewall-Bouncer
#   lib:
#     - lib/systemd-hardening.nix
#   services:
#     - crowdsec
#     - crowdsec-firewall-bouncer
#   tags:
#     - security
#     - crowdsec
#     - firewall
# ---
{
  config,
  lib,
  ...
}:
let
  cfgCrowdsec = config.my.security.crowdsec;
  hardening = import ../../lib/systemd-hardening.nix { inherit lib; };
  crowdsecCredFile = "/var/lib/crowdsec/local_api_credentials.yaml";
  crowdsecPort = config.my.ports.crowdsec;
in
{
  options.my.security.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec security engine and nftables firewall bouncer";
  };

  config = lib.mkIf cfgCrowdsec.enable {
    systemd.services = {
      crowdsec.serviceConfig = lib.mkMerge [
        (hardening.mkHardened {
          rw = [ "/var/lib/crowdsec" ];
          mdwx = false;
        })
        {
          StateDirectory = "crowdsec";
        }
      ];
      crowdsec-firewall-bouncer.serviceConfig = hardening.mkHardened {
        caps = [ "CAP_NET_ADMIN" ];
        mdwx = false;
      };
    };

    services = {
      crowdsec = {
        enable = true;
        autoUpdateService = true;
        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
          "crowdsecurity/caddy"
        ];
        localConfig.acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
            labels.type = "sshd";
          }
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=caddy.service" ];
            labels.type = "caddy";
          }
          {
            # nftables Drop-Logs: "nftables-dropped: " prefix landet im Kernel-Syslog.
            source = "journalctl";
            journalctl_filter = [ "SYSLOG_IDENTIFIER=kernel" ];
            labels.type = "syslog";
          }
        ];
        settings = {
          lapi.credentialsFile = crowdsecCredFile;
          general.api.server = {
            enable = true;
            listen_uri = "127.0.0.1:${toString crowdsecPort}";
          };
        };
      };

      crowdsec-firewall-bouncer = {
        enable = true;
        registerBouncer.enable = true;
        settings = {
          api_url = "http://127.0.0.1:${toString crowdsecPort}/";
          mode = "nftables";
          nftables = {
            ipv4_set_name = "crowdsec_blocked_ipv4";
            table = "inet filter";
            chain = "input";
            ipv6.enabled = config.my.security.firewall.ipv6;
          }
          // lib.optionalAttrs config.my.security.firewall.ipv6 {
            ipv6_set_name = "crowdsec_blocked_ipv6";
          };
        };
      };
    };
  };
}
