# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Cockpit Server Admin UI
#   lib:
#     - lib/caddy-helpers.nix
#   services:
#     - cockpit
#   tags:
#     - forge
#     - cockpit
# ---
{
  config,
  lib,
  pkgs,
  ...
}:

let
  caddy = import ../../lib/caddy-helpers.nix { inherit lib; };
  cfgCockpit = config.my.services.cockpit;
  domain = config.my.configs.identity.domain;

in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
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
    # ── COCKPIT SERVER ADMIN UI ───────────────────────────────────────────────
    (lib.mkIf cfgCockpit.enable {
      services = {
        cockpit = {
          enable = true;
          inherit (cfgCockpit) port;
        };

        caddy.virtualHosts = {
          # ── SECURE INTEL AMT INGRESS (SSO POCKET-ID GATEKEEPER) ─────────────
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
        pkgs.cockpit-machines
      ];
    })
  ];
}
