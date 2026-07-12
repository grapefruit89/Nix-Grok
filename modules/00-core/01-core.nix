# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Globale Options (Systemschema) + Basis-Systemkonfiguration (Locale, Journald)
#   docs:
#     - docs/adr/013-flake-portability.md
#   tags:
#     - core
#     - locale
#     - boot
# ---
{
  config,
  lib,
  ...
}:
let
  cfgJournald = config.my.core.journald;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my = {
    core = {
      journald.maxUse = lib.mkOption {
        type = lib.types.str;
        default = "500M";
        description = ''
          Maximale Journal-Größe (SystemMaxUse). Verhindert unbegrenztes Wachstum von
          /var/log/journal ohne Impermanence. 500M = ausreichend für Debugging auf kleinen SSDs.
          Auf Systemen mit viel Disk (≥ 500 GB) kann dieser Wert auf 1–2G erhöht werden.
        '';
      };
      journald.maxRetention = lib.mkOption {
        type = lib.types.str;
        default = "90day";
        description = "Maximale Journal-Retention (MaxRetentionSec). 90 Tage für Incident-Analyse; auf Impermanence irrelevant.";
      };
      nix-tuning = {
        enable = lib.mkEnableOption "Nix store performance tuning and GC";
        maxJobs = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Parallele Nix-Jobs (null = RAM-basiert). q958/i3-9100: 4.";
        };
        cores = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Kerne pro Job (0 = alle). null = RAM-basiert.";
        };
        daemonLowPriority = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "true = nix-daemon idle (schont Dienste). false = volle Build-Power.";
        };
      };
      zram-swap.enable = lib.mkEnableOption "Aggressive komprimierter ZRAM RAM-swap";
      # kernel-slim Option lebt jetzt nur noch in modules/20-security/2025-kernel-policy.nix (Duplikat entfernt)
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "development"
        "production"
      ];
      default = "development";
      description = "Overall system mode: development (open) or production (hardened)";
    };

    configs = {
      identity = {
        user = lib.mkOption {
          type = lib.types.str;
          description = "Primary user name (set in users/<name>/profile.nix).";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Primary domain (set in users/<name>/profile.nix).";
        };
      };
      locale = {
        default = lib.mkOption {
          type = lib.types.str;
          default = "de_DE.UTF-8";
          description = "System-wide default locale.";
        };
        language = lib.mkOption {
          type = lib.types.str;
          default = "de";
          description = "System-wide keyboard layout and language code.";
        };
        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/Berlin";
          description = "System-wide timezone.";
        };
      };
      hardware = {
        ramGB = lib.mkOption {
          type = lib.types.int;
          description = "Installed RAM in GB (set in machines/<host>/profile.nix).";
        };
        nixStoreGB = lib.mkOption {
          type = lib.types.int;
          description = "Nix-Store-Partition-Größe in GB — bestimmt GC-Trigger (min-free/max-free).";
        };
        renderDevice = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "GPU render node for VA-API (e.g. /dev/dri/renderD128). Empty = no VA-API consumers.";
        };
      };
      server = {
        lanIP = lib.mkOption {
          type = lib.types.str;
          description = "Server LAN IP (set in machines/<host>/profile.nix).";
        };
        netbirdIP = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Server Netbird IP (nach 'netbird up' mit 'netbird status' ermitteln und in profile.nix eintragen).";
        };
      };
      network = {
        dnsBootstrap = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                ip = lib.mkOption {
                  type = lib.types.str;
                  description = "Server-IP.";
                };
                hostname = lib.mkOption {
                  type = lib.types.str;
                  description = "TLS-Hostname fuer SNI.";
                };
              };
            }
          );
          default = [
            {
              ip = "1.1.1.1";
              hostname = "cloudflare-dns.com";
            }
            {
              ip = "9.9.9.9";
              hostname = "dns.quad9.net";
            }
            {
              ip = "149.112.112.112";
              hostname = "dns.quad9.net";
            }
          ];
          description = "DoT-Nameserver — Single Source of Truth für resolved + Blocky-Forwarder. Niemals Klartext-IP.";
        };
        ipv6 = {
          disableOnInterfaces = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Physische Interfaces ohne IPv6 (sysctl + systemd-networkd). Netbird/WG nicht listen.";
          };
          firewall = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "false = keine CrowdSec/nftables IPv6-Regeln (Homelab nur v4 auf LAN).";
          };
        };
        netbirdCidr = lib.mkOption {
          type = lib.types.str;
          default = "100.64.0.0/10";
          description = "Netbird-Mesh-CIDR (CGNAT) — private_admin, nftables, systemd IPAddressAllow.";
        };
        wanBogonCidrs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "127.0.0.0/8"
            "169.254.0.0/16"
          ];
          description = "WAN ingress anti-spoof — RFC1918, loopback, link-local.";
        };
      };
    };

    # my.ports.* → 08-ports.nix
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    {
      # Locale-Mapping aus zentralen my.configs.locale-Optionen (Werte in machines/<host>/profile.nix)
      time.timeZone = config.my.configs.locale.timezone;
      i18n.defaultLocale = config.my.configs.locale.default;
      console.keyMap = config.my.configs.locale.language;

      # nix-ld: ungepatche dynamische Binaries ausführbar machen (Dev-Komfort, kein Security-Impact)
      programs.nix-ld.enable = true;

      # Journal-Größe begrenzen (ohne Impermanence wächst /var/log/journal unbegrenzt).
      # Werte konfigurierbar via my.core.journald.maxUse + .maxRetention.
      services.journald.extraConfig = lib.mkDefault ''
        SystemMaxUse=${cfgJournald.maxUse}
        MaxRetentionSec=${cfgJournald.maxRetention}
      '';
    }

  ];
}
