# ---
# schema: "109x=Infrastruktur-Band (kein Service-Port)"
# meta:
#   layer: 3
#   role: module
#   purpose: Netbird Self-Hosted VPN + Privado WireGuard Split-Tunnel (UID-basiert)
#   services:
#     - netbird
#     - privado-vpn
#   docs:
#     - docs/adr/2030-networkd-wait-online-headless.md
#     - docs/adr/1025-pocket-id-oidc-provider.md
#   tags:
#     - vpn
#     - netbird
#     - wireguard
# ---
{
  config,
  lib,
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
        default = "";
        description = "WireGuard interface address — aus machines/<host>/profile.nix (z. B. p.network.privado.address).";
      };
      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          VPN-DNS für Usenet-Sandbox — aus machines/<host>/profile.nix (z. B. p.network.privado.dns).
          Bewusst NICHT als DNS= in systemd.network: Usenet-Dienste binden /etc/usenet-resolv.conf
          (modules/50-media/57-usenet-confinement) — Host-DNS bleibt auf resolved/DoT.
        '';
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
          # Lokal: pocket-id direkt — hairpin NAT über externe IP nicht möglich
          oidcConfigEndpoint = "http://127.0.0.1:${toString config.my.ports.pocket-id}/.well-known/openid-configuration";
          metricsPort = config.my.ports.netbird-metrics;
          settings.DataStoreEncryptionKey._secret = "/var/lib/secrets/netbird-mgmt-encryption-key";
        };
        signal = {
          enableNginx = false;
          # pprof im management-Binary hardcoded 6060 — signal nutzt my.ports.netbird-signal-metrics
          metricsPort = config.my.ports.netbird-signal-metrics;
        };
        dashboard.settings = {
          AUTH_AUTHORITY = "https://auth.${domain}";
        };
      };

      services.netbird.clients.default = {
        interface = "wt0";
        port = config.my.ports.netbird-wg;
        openFirewall = true;
        login = {
          enable = true;
          setupKeyFile = cfgNetbird.setupKeyFile;
        };
      };

      # Legacy networking.firewall nur vor Stufe 8. Ab Stufe 8+: nftables (lib/nftables-rules.nix).
      networking.firewall = lib.mkIf (!config.my.security.firewall.enable) {
        trustedInterfaces = [ "wt0" ];
        checkReversePath = "loose";
        allowedUDPPorts = [
          config.my.ports.netbird-stun
          config.my.ports.netbird-signal
        ];
        allowedTCPPorts = [
          config.my.ports.netbird-management
          config.my.ports.netbird-signal
        ];
      };

      my.impermanence.extraPaths = [ "/var/lib/netbird-default" ];
    })

    # ── PRIVADO VPN WIREGUARD CLIENT ──────────────────────────────────────────
    (lib.mkIf config.my.services.privado-vpn.enable (
      let
        cfgPrivado = config.my.services.privado-vpn;
        vpnTable = config.my.network.routing.privadoTableId;
        tableName = config.my.network.routing.privadoTableName;
        # Prowlarr + SABnzbd — nur Registry-UIDs über privado (Split-Tunnel)
        vpnUids = [
          config.my.users.registry.prowlarr
          config.my.users.registry.sabnzbd
        ];
        uidPolicyRules = map (uid: {
          User = "${toString uid}-${toString uid}";
          Table = tableName;
          Priority = config.my.network.routing.uidRulePriorityBase + uid;
        }) vpnUids;
      in
      {
        # Deklarativ via systemd-networkd — kein wg-quick postUp/preDown (ip rule/route).
        # privado.dns → nur Usenet-Sandbox (/etc/usenet-resolv.conf), nicht [Network] DNS= hier.
        systemd.network.config.routeTables = {
          ${tableName} = vpnTable;
        };

        systemd.network.netdevs.privado = {
          netdevConfig = {
            Kind = "wireguard";
            Name = "privado";
          };
          wireguardConfig = {
            PrivateKeyFile = cfgPrivado.privateKeyFile;
          };
          wireguardPeers = [
            {
              PublicKey = cfgPrivado.publicKey;
              Endpoint = cfgPrivado.endpoint;
              AllowedIPs = [ "0.0.0.0/0" ];
              PersistentKeepalive = 25;
            }
          ];
        };

        systemd.network.networks.privado = {
          matchConfig.Name = "privado";
          address = [ cfgPrivado.ipAddress ];
          routes = [
            {
              Destination = "0.0.0.0/0";
              Table = tableName;
            }
          ];
          routingPolicyRules = uidPolicyRules;
        };

        # Privado ist optional (Key fehlt auf niedrigen Stufen) — nicht für network-online zählen.
        systemd.network.wait-online.ignoredInterfaces = lib.mkAfter [ "privado" ];

        assertions = [
          {
            assertion = cfgPrivado.ipAddress != "";
            message = "my.services.privado-vpn.ipAddress fehlt — machines/<host>/profile.nix → p.network.privado.address.";
          }
          {
            assertion = cfgPrivado.publicKey != "";
            message = "my.services.privado-vpn.publicKey fehlt — machines/<host>/profile.nix → p.network.privado.publicKey.";
          }
          {
            assertion = cfgPrivado.endpoint != "";
            message = "my.services.privado-vpn.endpoint fehlt — machines/<host>/profile.nix → p.network.privado.endpoint.";
          }
        ];
      }
    ))
  ];
}
