{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfgNetbird = config.my.services.netbird;
  domain = config.my.configs.identity.domain;
in
{
  # ============================================================================
  # OPTIONS
  # ============================================================================
  options.my.services = {
    # 🌐 Netbird Self-Hosted VPN
    netbird = {
      enable = lib.mkEnableOption "Netbird Self-Hosted VPN (Management + Signal + Client)";
      domain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Domain for Netbird management server (e.g. netbird.example.com).";
      };
      setupKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/secrets/netbird_setup_key";
        description = "Path to file containing the Netbird setup key for auto-login.";
      };
    };

    # 🛡️ Privado VPN WireGuard Client
    privado-vpn = {
      enable = lib.mkEnableOption "Privado VPN WireGuard Client Tunnel";
      ipAddress = lib.mkOption {
        type = lib.types.str;
        default = "10.0.0.2/32";
        description = "Privado VPN interface IP address.";
      };
      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "10.255.255.255" ];
        description = "DNS servers to bind to the VPN interface.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Privado VPN server WireGuard public key.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Privado VPN server endpoint IP and port.";
      };
      privateKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/secrets/privado_private_key";
        description = "WireGuard private key file — Pfad aus machines/<host>/profile.nix.";
      };
    };
  };

  # ============================================================================
  # CONFIG
  # ============================================================================
  config = lib.mkMerge [
    # ── NETBIRD SELF-HOSTED VPN ───────────────────────────────────────────────
    (lib.mkIf cfgNetbird.enable {
      services.netbird.server = {
        enable = true;
        domain = cfgNetbird.domain;
        enableNginx = false;
        management = {
          enableNginx = false;
          domain = cfgNetbird.domain;
          turnDomain = cfgNetbird.domain;
          # Lokal: pocket-id Port 1001 direkt — hairpin NAT über externe IP nicht möglich
          oidcConfigEndpoint = "http://127.0.0.1:1001/.well-known/openid-configuration";
          metricsPort = 6061;
          settings.DataStoreEncryptionKey._secret = "/var/lib/secrets/netbird-mgmt-encryption-key";
        };
        signal = {
          enableNginx = false;
          # pprof-Port des management-Binary ist hardcoded 6060 — signal auf 6062 verschieben
          metricsPort = 6062;
        };
        dashboard.settings = {
          AUTH_AUTHORITY = "https://auth.${domain}";
        };
      };

      services.netbird.clients.default = {
        interface = "wt0";
        port = 51820;
        openFirewall = true;
        login = {
          enable = true;
          setupKeyFile = cfgNetbird.setupKeyFile;
        };
      };

      networking.firewall = {
        trustedInterfaces = [ "wt0" ];
        checkReversePath = "loose";
        allowedUDPPorts = [
          3478
          10000
        ];
        allowedTCPPorts = [
          33073
          10000
        ];
      };

      my.impermanence.extraPaths = [ "/var/lib/netbird-default" ];
    })

    # ── PRIVADO VPN WIREGUARD CLIENT ──────────────────────────────────────────
    (lib.mkIf
      (config.my.services.privado-vpn.enable && !(config.my.services.vpn-confinement.enable or false))
      {
        networking.wg-quick.interfaces.privado =
          let
            ip = pkgs.iproute2;
            vpnTable = "51820";
            # Prowlarr + SABnzbd — nur Registry-UIDs über privado (Split-Tunnel)
            vpnUids = [
              config.my.users.registry.prowlarr
              config.my.users.registry.sabnzbd
            ];
            uidRules = lib.concatMapStringsSep "\n" (
              uid:
              "${ip}/bin/ip rule add uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid}"
            ) vpnUids;
            uidRulesDown = lib.concatMapStringsSep "\n" (
              uid:
              "${ip}/bin/ip rule del uidrange ${toString uid}-${toString uid} lookup ${vpnTable} priority 9${toString uid} || true"
            ) vpnUids;
          in
          {
            autostart = true;
            address = [ config.my.services.privado-vpn.ipAddress ];
            # Split-Tunnel (table=off): kein resolv.conf via wg-quick — vermeidet resolvconf-Signatur-Konflikt
            dns = [ ];
            privateKeyFile = config.my.services.privado-vpn.privateKeyFile;
            table = "off";

            postUp = ''
              ${ip}/bin/ip route add default dev privado table ${vpnTable}
              ${uidRules}
            '';
            preDown = ''
              ${uidRulesDown}
              ${ip}/bin/ip route flush table ${vpnTable} || true
            '';

            peers = [
              {
                publicKey = config.my.services.privado-vpn.publicKey;
                endpoint = config.my.services.privado-vpn.endpoint;
                allowedIPs = [ "0.0.0.0/0" ];
                persistentKeepalive = 25;
              }
            ];
          };
      }
    )
  ];
}
