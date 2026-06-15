# q958 — Netzwerk-Verdrahtung aus profile.nix (keine Keys, keine Widersprüche)
{ config, lib, ... }:

let
  p = import ./profile.nix;
  secretsDir = p.secrets.dir;
  secretPath = name: "${secretsDir}/${p.secrets.files.${name}}";
in
{
  my.configs.network = {
    dnsDoH = p.network.dns.doh;
    dnsBootstrap = p.network.dns.bootstrap;
    dnsFallback = p.network.dns.fallback;
  };

  my.services = {
    blocky.upstreamDns = p.network.blocky.upstream;
    pocket-id.secretsFile = secretPath "pocketId";
    privado-vpn.privateKeyFile = secretPath "privadoKey";
  };

  networking.firewall.allowedUDPPorts = lib.mkIf (
    config.my.services.tailscale.enable && !config.my.security.firewall.enable
  ) (lib.mkForce [ config.my.services.tailscale.port ]);
}