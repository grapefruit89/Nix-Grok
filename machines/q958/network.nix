# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Verdrahtung Netzwerk — Blocky, Netbird, Pocket-ID, Privado
#   services:
#     - blocky
#     - netbird
#     - pocket-id
#   tags:
#     - network
#     - dns
# ---
{
  config,
  lib,
  ...
}:
let
  p = import ./profile.nix;
  lan = p.network.lan;
  secretsDir = p.secrets.dir;
  secretPath = name: "${secretsDir}/${p.secrets.files.${name}}";
  primaryUser = import ../../users/jarvis/profile.nix;
  blockyAllowlist = import ../../lib/blocky-allowlist.nix { user = primaryUser; };
  dnsPort = config.my.network.protocol.dns;
in
{
  my.configs.network = {
    dnsBootstrap = p.network.dns.bootstrap;
    netbirdCidr = p.network.netbirdCidr;
    ipv6 = {
      disableOnInterfaces = p.network.ipv6.disableOnInterfaces;
      firewall = p.network.ipv6.firewall;
    };
  };

  my.security.firewall.ipv6 = p.network.ipv6.firewall;

  my.services = {
    ddns-updater.wanInterface = lan.interface;
    blocky.allowlistFile = blockyAllowlist.file;
    netbird.domain = "netbird.${config.my.configs.identity.domain}";
    netbird.setupKeyFile = secretPath "netbirdSetupKey";
    pocket-id.secretsFile = secretPath "pocketId";
    privado-vpn = {
      privateKeyFile = secretPath "privadoKey";
      ipAddress = p.network.privado.address;
      publicKey = p.network.privado.publicKey;
      endpoint = p.network.privado.endpoint;
      dns = p.network.privado.dns;
    };
  };

  networking.firewall.interfaces.${lan.interface} =
    lib.mkIf (config.my.services.blocky.enable && !config.my.security.firewall.enable)
      {
        allowedUDPPorts = [ dnsPort ];
        allowedTCPPorts = [ dnsPort ];
      };

  systemd.tmpfiles.rules = lib.mkIf config.my.services.blocky.enable [
    blockyAllowlist.tmpfilesRule
  ];

  assertions = lib.optionals config.my.services.blocky.enable [
    {
      assertion = config.my.services.blocky.allowlistFile == blockyAllowlist.file;
      message = "[BLOCKY] allowlistFile weicht von lib/blocky-allowlist.nix ab — nur blockyAllowlist.{file,tmpfilesRule} in network.nix verwenden.";
    }
  ];
}
