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
  pkgs,
  ...
}:
let
  cfgCrowdsec = config.my.security.crowdsec;
  hardening = import ../../lib/systemd-hardening.nix { inherit lib; };
  yaml = pkgs.formats.yaml { };
in
{
  options.my.security.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec security engine and nftables firewall bouncer";
  };

  config = lib.mkIf cfgCrowdsec.enable (
    let
      crowdsecEtcConfig = yaml.generate "crowdsec-etc.yaml" config.services.crowdsec.settings.general;

      crowdsecCredFile = "/var/lib/crowdsec/local_api_credentials.yaml";
      crowdsecCollections = lib.concatMapStringsSep " " lib.escapeShellArg [
        "crowdsecurity/linux"
        "crowdsecurity/sshd"
        "crowdsecurity/caddy"
      ];

      crowdsecSetupFixed = pkgs.writeShellScript "crowdsec-setup-fixed" ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/crowdsec/state/hub/
        ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml hub update
        ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml collections install ${crowdsecCollections} || true
        ${lib.getExe' pkgs.crowdsec "cscli"} -c /etc/crowdsec/config.yaml machines add ${config.networking.hostName} --auto --force -f "${crowdsecCredFile}"
      '';

      crowdsecPostSetup = pkgs.writeShellScript "crowdsec-post-setup" ''
        _port="${toString config.my.ports.crowdsec}"
        ${pkgs.findutils}/bin/find /var/lib/crowdsec -type f 2>/dev/null | while read -r _f; do
          ${pkgs.gnused}/bin/sed -i \
            -e "s|:8080/|:$_port/|g" \
            -e "s|:8088/|:$_port/|g" \
            -e "s|:8080|:$_port|g" \
            -e "s|:8088|:$_port|g" \
            "$_f" || true
        done
        ${pkgs.coreutils}/bin/rm -rf /var/lib/crowdsec-firewall-bouncer-register 2>/dev/null || true
      '';
    in
    {
      systemd = {
        tmpfiles.rules = [
          "d /etc/crowdsec 0755 root root -"
          "L+ /etc/crowdsec/config.yaml - - - - ${crowdsecEtcConfig}"
          "d /var/lib/crowdsec 0755 root root -"
          "d /var/lib/crowdsec/data 0755 crowdsec crowdsec -"
          "d /var/lib/crowdsec/config 0755 crowdsec crowdsec -"
          "d /var/lib/crowdsec/hub 0755 crowdsec crowdsec -"
        ];
        services = {
          crowdsec.serviceConfig = lib.mkMerge [
            (hardening.mkHardened {
              rw = [ "/var/lib/crowdsec" ];
              mdwx = false;
            })
            {
              ExecStartPre = lib.mkOverride 50 [
                " "
                crowdsecSetupFixed
                "${lib.getExe' pkgs.crowdsec "crowdsec"} -c /etc/crowdsec/config.yaml -t -error"
                crowdsecPostSetup
              ];
              StateDirectory = "crowdsec";
            }
          ];
          crowdsec-firewall-bouncer.serviceConfig = hardening.mkHardened {
            caps = [ "CAP_NET_ADMIN" ];
            mdwx = false;
          };
        };
      };

      services = {
        crowdsec = {
          enable = true;
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
          ];
          settings = {
            general.api = {
              client.credentials_path = lib.mkForce crowdsecCredFile;
              server = {
                enable = true;
                listen_uri = "127.0.0.1:${toString config.my.ports.crowdsec}";
              };
            };
          };
        };

        crowdsec-firewall-bouncer = {
          enable = true;
          registerBouncer.enable = true;
          settings = {
            api_url = "http://127.0.0.1:${toString config.my.ports.crowdsec}/";
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
    }
  );
}
