# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Forgejo Git, Semaphore Ansible-UI, Cockpit
#   lib:
#     - lib/unix-sockets.nix
#   services:
#     - forgejo
#     - semaphore
#   tags:
#     - forge
#     - git
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  caddy = import ../lib/caddy-helpers.nix { inherit lib; };
  sockets = import ../lib/unix-sockets.nix { inherit lib; };
  cfgForgejo = config.my.services.forgejo;
  cfgSemaphore = config.my.services.semaphore;
  cfgCockpit = config.my.services.cockpit;
  domain = config.my.configs.identity.domain;

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    forgejo = {
      enable = lib.mkEnableOption "Forgejo self-hosted Git service";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.forgejo;
        description = "Forgejo HTTP port.";
      };
      disableRegistration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable public user registration.";
      };
    };

    semaphore = {
      enable = lib.mkEnableOption "Semaphore Ansible Web UI";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.semaphore;
        description = "Semaphore HTTP port.";
      };
    };

    cockpit = {
      enable = lib.mkEnableOption "Cockpit Server Admin UI";
      port = lib.mkOption {
        type = lib.types.port;
        default = config.my.ports.cockpit;
        description = "Cockpit admin port.";
      };
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
            PROTOCOL = "http+unix";
            HTTP_ADDR = sockets.forgejo;
            ROOT_URL = "https://git.${domain}/";
          };
          service.DISABLE_REGISTRATION = cfgForgejo.disableRegistration;
        };
      };

      systemd.services.forgejo.serviceConfig = {
        RuntimeDirectoryMode = "0755";
        # Caddy reverse_proxy braucht Zugriff auf http+unix-Socket
        ExecStartPost = [
          "+${pkgs.coreutils}/bin/chmod 0666 ${sockets.forgejo}"
        ];
      };

      my.impermanence.extraPaths = [ "/var/lib/forgejo" ];
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
            SEMAPHORE_PLAYBOOK_PATH = "/var/lib/semaphore/playbooks";
            SEMAPHORE_DB_PATH = "/var/lib/semaphore/semaphore.db";
          };
          volumes = [
            "/var/lib/semaphore:/var/lib/semaphore"
          ];
        };
      };

      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };

      my.impermanence.extraPaths = [ "/var/lib/semaphore" ];
    })

    # ── COCKPIT SERVER ADMIN UI ───────────────────────────────────────────────
    (lib.mkIf cfgCockpit.enable {
      services = {
        cockpit = {
          enable = true;
          inherit (cfgCockpit) port;
        };

        caddy.virtualHosts = {
          # ── SECURE INTEL AMT INGRESS (SSO POCKET-ID GATEKEEPER) ─────────────────
          "machines.${domain}" = lib.mkIf (cfgCockpit.exposeAmt && cfgCockpit.amtHost != "") {
            extraConfig = caddy.mkProxy {
              port = cfgCockpit.amtPort;
              host = cfgCockpit.amtHost;
              imports = [ "sso_auth" ];
            };
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
