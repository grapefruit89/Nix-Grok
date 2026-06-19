{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.services.hermes;
in
{
  config = lib.mkIf cfg.enable {
    # Hermes-Agent-Flake: eigener System-User, State unter /data/state/hermes
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      environmentFiles = [ "/data/state/hermes/env" ];

      settings = {
        model.default = "gemini-3-flash-preview";
        model.provider = "google-gemini-cli";
        context_compression = {
          threshold = 70;
          target_ratio = 0.30;
          protect_last = 15;
          protect_first = 2;
        };
        # Agent-Befehle nur nach Freigabe — siehe hermes-agent Security-Docs
        security = {
          command_approval = true;
        };
      };

    };

    # Strikte Systemd-Sandbox für Hermes-Agent (KISS & Secure)
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      home = "/data/state/hermes";
    };
    users.groups.hermes = { };

    systemd.services.hermes-agent.serviceConfig = {
      User = lib.mkForce "hermes";
      Group = lib.mkForce "hermes";
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "/data/state/hermes" ];
    };

    # Secrets für Hermes (API-Keys) — Context7 optional aus /var/lib/secrets
    systemd.services.hermes-env-provision = {
      description = "Provision /data/state/hermes/env for Hermes Agent";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "hermes-env-provision" ''
          set -euo pipefail
          install -d -m 2770 -o hermes -g hermes /data/state/hermes
          install -d -m 2770 -o hermes -g hermes /data/state/hermes/.hermes
          touch /data/state/hermes/env
          chown hermes:hermes /data/state/hermes/env
          chmod 0640 /data/state/hermes/env
          if [ -f /home/moritz/secrets/context7.env ]; then
            grep -q '^CONTEXT7_API_KEY=' /home/moritz/secrets/context7.env 2>/dev/null && \
              grep '^CONTEXT7_API_KEY=' /home/moritz/secrets/context7.env >> /data/state/hermes/env || true
          fi
        '';
      };
      wantedBy = [ "multi-user.target" ];
      before = [ "hermes-agent.service" ];
    };

    # Context7: Key in /data/state/hermes/env (aus context7.env) — dann:
    #   hermes mcp add context7 --url https://mcp.context7.com/mcp --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

    # Kein root-WebUI — Gateway läuft als User hermes mit upstream-Härtung
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeGatewayPort [ cfg.port ];
  };
}
