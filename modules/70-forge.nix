/*
---
id: 70-forge
upstream_repo: "forgejo/forgejo"
---
*/

# ==============================================================================
# PURPOSE
# ==============================================================================
# Configures the forge ecosystem: Forgejo (git hosting), Semaphore (Ansible UI),
# and Cockpit (system administration).
# Key decisions -> ADR-70-forge.md

{ config, lib, pkgs, ... }:

let
  cfgForgejo = config.my.services.forgejo;
  cfgSemaphore = config.my.services.semaphore;
  cfgCockpit = config.my.services.cockpit;
  cfgMdBook = config.my.services.mdbook;
  domain = config.my.configs.identity.domain;

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    forgejo = {
      enable = lib.mkEnableOption "Forgejo self-hosted Git service";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.forgejo; description = "Forgejo HTTP port."; };
      disableRegistration = lib.mkOption { type = lib.types.bool; default = true; description = "Disable public user registration."; };
    };

    mdbook = {
      enable = lib.mkEnableOption "mdBook SSoT Interactive Docs";
      port = lib.mkOption { type = lib.types.port; default = 6200; description = "mdBook HTTP port."; };
    };

    semaphore = {
      enable = lib.mkEnableOption "Semaphore Ansible Web UI";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.semaphore; description = "Semaphore HTTP port."; };
    };

    cockpit = {
      enable = lib.mkEnableOption "Cockpit Server Admin UI";
      port = lib.mkOption { type = lib.types.port; default = config.my.ports.cockpit; description = "Cockpit admin port."; };
      enableVirtualization = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Libvirtd KVM hypervisor and cockpit-machines management UI.";
      };
      exposeAmt = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose Intel AMT via Caddy (requires amtHost in machines/<host>/profile.nix).";
      };
      amtHost = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Intel AMT host (set in machines/<host>/profile.nix).";
      };
      amtPort = lib.mkOption {
        type = lib.types.port;
        default = 16992;
        description = "Intel AMT port.";
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── FORGEJO GIT SERVICE ───────────────────────────────────────────────────
    (lib.mkIf cfgForgejo.enable {
      services.forgejo = {
        enable = true;
        database = {
          type = "postgres";
          createDatabase = true;
          user = "forgejo";
          name = "forgejo";
          socket = "/run/postgresql";
        };
        settings = {
          server = {
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = cfgForgejo.port;
            ROOT_URL = "https://git.${domain}/";
          };
          service.DISABLE_REGISTRATION = cfgForgejo.disableRegistration;
        };
      };

      services.caddy.virtualHosts."git.${domain}" = {
        extraConfig = ''
          import security_headers
          reverse_proxy 127.0.0.1:${toString cfgForgejo.port}
        '';
      };
    })

    # ── MDBOOK INTERACTIVE DOCS ───────────────────────────────────────────────
    (lib.mkIf cfgMdBook.enable {
      systemd.services.mdbook-docs = {
        description = "mdBook SSoT Interactive Docs Server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          # Serve from persistent source or tmpfs rendering directory
          ExecStart = "${pkgs.mdbook}/bin/mdbook serve /data/state/mdbook -p ${toString cfgMdBook.port} -n 127.0.0.1";
          Restart = "always";
          User = "nobody";
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      services.caddy.virtualHosts."docs.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgMdBook.port}
        '';
      };
    })

    # ── SEMAPHORE ANSIBLE WEB UI ──────────────────────────────────────────────
    (lib.mkIf cfgSemaphore.enable {
      virtualisation.oci-containers = {
        backend = "podman";
        containers.semaphore = {
          image = "docker.io/semaphoreui/semaphore:latest";
          ports = [ "127.0.0.1:${toString cfgSemaphore.port}:3000" ];
          environment = {
            SEMAPHORE_DB_DIALECT = "sqlite";
            SEMAPHORE_PLAYBOOK_PATH = "/data/state/semaphore/playbooks";
            SEMAPHORE_DB_PATH = "/data/state/semaphore/semaphore.db";
          };
          volumes = [
            "/data/state/semaphore:/data/state/semaphore"
          ];
        };
      };

      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };

      services.caddy.virtualHosts."semaphore.${domain}" = {
        extraConfig = ''
          import sso_auth
          reverse_proxy 127.0.0.1:${toString cfgSemaphore.port}
        '';
      };
    })

    # ── COCKPIT SERVER ADMIN UI ───────────────────────────────────────────────
    (lib.mkIf cfgCockpit.enable {
      services = {
        cockpit = {
          enable = true;
          inherit (cfgCockpit) port;
        };

        caddy.virtualHosts = {
          "admin.${domain}" = {
            extraConfig = ''
              import sso_auth
              reverse_proxy 127.0.0.1:${toString cfgCockpit.port}
            '';
          };

          # ── SECURE INTEL AMT INGRESS (SSO POCKET-ID GATEKEEPER) ─────────────────
          "machines.${domain}" = lib.mkIf (cfgCockpit.exposeAmt && cfgCockpit.amtHost != "") {
            extraConfig = ''
              import sso_auth
              reverse_proxy ${cfgCockpit.amtHost}:${toString cfgCockpit.amtPort}
            '';
          };
        };
      };

      # ── KVM VIRTUALIZATION ENGINE (COCKPIT /MACHINES PATH) ──────────────────
      virtualisation.libvirtd = lib.mkIf cfgCockpit.enableVirtualization {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
        };
      };

      environment.systemPackages = lib.mkIf cfgCockpit.enableVirtualization [
        pkgs.cockpit-machines # Exposes the native /machines tab inside Cockpit UI
      ];
    })
  ];
}

