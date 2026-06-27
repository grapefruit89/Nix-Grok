# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Kernel- und System-Härtung (sysctl, Boot-Parameter, Mount-Flags)
#   docs:
#     - docs/guides/GUIDE-security-secrets.md
#   tags:
#     - security
#     - kernel
#     - sysctl
# ---
{
  config,
  lib,
  ...
}: let
  cfg = config.my.security.kernel-hardening;
  vpnNeedsForward = config.my.services.vpn-confinement.enable or false;
in {
  options.my.security.kernel-hardening = {
    enable = lib.mkEnableOption "Kernel sysctl, boot-parameter and mount hardening";

    disableIpv6Stack = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable IPv6 globally — false: Jellyfin/.NET braucht ::1; LAN-v6 bleibt via 10-network aus.";
    };

    hardenTmp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mount /tmp with noexec,nosuid,nodev.";
    };

    hardenDevShm = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    hardenRunLock = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    enableSlubHardening = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    panicOnOops = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reboot on kernel Oops (server mode).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.editor = lib.mkDefault false;

    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.hardenTmp {
        "/tmp" = {
          device = "tmpfs";
          fsType = "tmpfs";
          options = [
            "defaults"
            "noexec"
            "nosuid"
            "nodev"
          ];
        };
      })
      (lib.mkIf cfg.hardenDevShm {
        "/dev/shm" = {
          device = "shm";
          fsType = "tmpfs";
          options = [
            "defaults"
            "size=50%"
            "noexec"
            "nosuid"
            "nodev"
          ];
        };
      })
      (lib.mkIf cfg.hardenRunLock {
        "/run/lock" = {
          device = "tmpfs";
          fsType = "tmpfs";
          options = [
            "defaults"
            "noexec"
            "nosuid"
            "nodev"
          ];
        };
      })
    ];

    boot.kernel.sysctl =
      {
        # Network baseline (ip_forward left to vpn-confinement when VPN active)
        "net.ipv6.conf.all.disable_ipv6" = lib.mkIf cfg.disableIpv6Stack 1;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.icmp_echo_ignore_all" = 1;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.conf.all.log_martians" = 1;
        "net.ipv4.conf.default.log_martians" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.tcp_timestamps" = 0;
        "net.ipv4.tcp_syn_retries" = 3;
        "net.ipv4.tcp_max_syn_backlog" = 4096;
        "net.ipv4.tcp_fin_timeout" = 15;
        "net.ipv6.conf.all.accept_ra" = 0;
        "net.ipv6.conf.default.accept_ra" = 0;
        "net.core.bpf_jit_harden" = 2;
        "net.core.rmem_max" = 212992;
        "net.core.wmem_max" = 212992;
        "net.ipv4.ip_unprivileged_port_start" = 1001; # pocket-id + other services with id >= 1001 bind directly

        # Memory / introspection
        "kernel.dmesg_restrict" = 1;
        "kernel.kptr_restrict" = 2;
        "kernel.yama.ptrace_scope" = 1;
        "kernel.sysrq" = 0;
        "kernel.unprivileged_bpf_disabled" = 1;
        "vm.unprivileged_userfaultfd" = 0;
        "vm.mmap_rnd_bits" = 32;

        # Filesystem
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;

        # Core dumps discarded
        "kernel.core_pattern" = "|/bin/false";
        "kernel.panic_on_oops" =
          if cfg.panicOnOops
          then 1
          else 0;
      }
      // lib.mkIf (!vpnNeedsForward) {
        "net.ipv4.ip_forward" = 0;
      };

    boot.kernelParams =
      [
        "slab_nomerge"
        "init_on_alloc=1"
        "init_on_free=1"
        "mitigations=auto"
        "io_delay=type0x80"
      ]
      ++ lib.optionals cfg.enableSlubHardening ["slub_debug=P"]
      ++ lib.optionals (config.my.mode == "production") ["page_poison=1"];

    boot.blacklistedKernelModules = [
      "thunderbolt"
      "firewire-core"
      "ohci1394"
      "kgdb"
    ];

    security.pam.loginLimits = [
      {
        domain = "*";
        type = "hard";
        item = "core";
        value = "0";
      }
    ];

    systemd.coredump.enable = lib.mkDefault false;
  };
}
