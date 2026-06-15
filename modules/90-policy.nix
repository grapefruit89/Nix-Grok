
# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures bubblewrap-based sandboxing policies (jailed-agents) for running
# autonomous LLM coding agents securely on the host.
# Key decisions → ADR-90-policy.md

{ config
, lib
, pkgs
, ...
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
