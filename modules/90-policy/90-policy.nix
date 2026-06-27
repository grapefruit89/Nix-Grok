# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Bubblewrap-Policies für jailed LLM-Coding-Agenten
#   services:
#     - jailed-agents
#   tags:
#     - policy
#     - sandbox
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # --------------------------------------------------------------------------
  # MODULE CONFIG REF
  # --------------------------------------------------------------------------
  cfg = config.my.policy.jailed-agents;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.policy.jailed-agents = {
    enable = lib.mkEnableOption "Bubblewrap-based zero-trust sandboxing for LLM agents";
  };

  # ============================================================================
  # CONFIG
  # The implementation. Guarded by lib.mkIf cfg.enable.
  # ============================================================================
  config = lib.mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # NETZWERK-SICHERHEITS-ASSERTIONS
    # --------------------------------------------------------------------------
    assertions = [
      {
        assertion =
          config.my.security.firewall.enable
          -> (config.my.services.blocky.enable || config.my.services.technitium-dns-server.enable);
        message = "POLICY: Firewall aktiviert, aber kein DNS-Resolver (Blocky/Technitium) — DNS-Leck möglich.";
      }
      {
        assertion = config.my.security.firewall.enable -> config.my.security.fail2ban.enable;
        message = "POLICY: Firewall ohne Fail2ban — Brute-Force-Schutz fehlt.";
      }
      {
        assertion = config.my.services.tailscale.enable -> config.my.security.firewall.tailscaleNotrack;
        message = "POLICY: Tailscale ohne NOTRACK — Performance-Problem bei VPN-Traffic.";
      }
      {
        assertion =
          config.my.services.vpn-confinement.enable -> config.my.security.firewall.skuidSegmentation.enable;
        message = "POLICY: VPN-Confinement ohne skuid-Segmentation — Usenet-UIDs können Firewall umgehen.";
      }
    ];

    # --------------------------------------------------------------------------
    # BUBBLEWRAP CAGE ENVIRONMENT
    # --------------------------------------------------------------------------
    systemd.services.jailed-agents = {
      description = "Zero-Trust LLM Coding Agent Jail Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        User = "jailed-agent";
        Group = "jailed-agent";

        # Sandbox hardening guidelines
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;

        StateDirectory = "jailed-agent";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    users.users.jailed-agent = {
      isSystemUser = true;
      group = "jailed-agent";
    };
    users.groups.jailed-agent = { };

    # We install bubblewrap to implement sandboxing policies
    environment.systemPackages = [ pkgs.bubblewrap ];
  };
}
