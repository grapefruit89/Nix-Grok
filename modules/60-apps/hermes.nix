# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Hermes-Agent Gateway mit Container-Isolation
#   services:
#     - hermes-agent
#   tags:
#     - hermes
#     - llm
# ---
{ config, lib, pkgs, ... }:

let
  cfg = config.my.services.hermes;
  identityUser = config.my.configs.identity.user;
in
{
  config = lib.mkIf cfg.enable {
    my.impermanence.extraPaths = [ "/var/lib/hermes" ];

    # Hermes-Agent-Flake: eigener System-User, State unter /var/lib/hermes
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      environmentFiles = [ "/var/lib/hermes/env" ];

      settings = {
        model.default = "deepseek-ai/deepseek-v4-flash";
        model.provider = "nvidia";
        fallback_providers = [
          { provider = "nvidia"; model = "meta/llama-3.3-70b-instruct"; }
          { provider = "nvidia"; model = "google/gemma-4-31b-it"; }
          { provider = "nvidia"; model = "deepseek-ai/deepseek-v4-pro"; }
        ];
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

    services.hermes-agent.container.enable = lib.mkIf cfg.containerMode true;
    services.hermes-agent.container.backend = lib.mkIf cfg.containerMode "podman";
    services.hermes-agent.container.hostUsers = lib.mkIf cfg.containerMode [ identityUser ];

    virtualisation.podman.enable = lib.mkIf cfg.containerMode true;

    # Secrets für Hermes (API-Keys) — Context7 optional aus /var/lib/secrets
    systemd.services.hermes-env-provision = {
      description = "Provision /var/lib/hermes/env for Hermes Agent";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "hermes-env-provision" ''
          set -euo pipefail
          install -d -m 2770 -o hermes -g hermes /var/lib/hermes
          install -d -m 2770 -o hermes -g hermes /var/lib/hermes/.hermes
          touch /var/lib/hermes/env
          chown hermes:hermes /var/lib/hermes/env
          chmod 0640 /var/lib/hermes/env
          if [ -f /var/lib/secrets/context7.env ]; then
            grep -q '^CONTEXT7_API_KEY=' /var/lib/secrets/context7.env 2>/dev/null && \
              grep '^CONTEXT7_API_KEY=' /var/lib/secrets/context7.env >> /var/lib/hermes/env || true
          fi
          if [ -f /var/lib/secrets/nvidia_nim_api_key ]; then
            echo "NVIDIA_API_KEY=$(cat /var/lib/secrets/nvidia_nim_api_key)" >> /var/lib/hermes/env
          fi
        '';
      };
      wantedBy = [ "multi-user.target" ];
      before = [ "hermes-agent.service" ];
    };

    # Context7: Key in /var/lib/hermes/env (aus context7.env) — dann:
    #   hermes mcp add context7 --url https://mcp.context7.com/mcp --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY"

    # Kein root-WebUI — Gateway läuft als User hermes mit upstream-Härtung
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.exposeGatewayPort [ cfg.port ];
  };
}