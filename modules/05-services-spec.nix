# ---
# meta:
#   id: NIXH-05-MOD-001
#   layer: 3
#   role: module
#   purpose: Service-Spec-Matrix (SSoT) — Zonen, Ports, Port-Duplikat-Assertions
#   docs:
#     - docs/SPEC_REGISTRY.md
#     - docs/ROADMAP.md
#   lib:
#     - lib/services-spec.nix
#     - lib/dns-map.nix
#   tags:
#     - services-spec
#     - ports
# ---
{ config, lib, ... }:

let
  specLib = import ../lib/services-spec.nix { inherit lib; };
  domain = config.my.configs.identity.domain;
  dnsMap = import ../lib/dns-map.nix { inherit domain; };
in
{
  options.my.services.spec = lib.mkOption {
    type = lib.types.attrsOf specLib.specEntryType;
    default = { };
    description = "Service specification matrix — zone, port/socket, ingress subdomain.";
  };

  config = {
    my.services.spec = specLib.mkDefaultSpec config.my.ports;

    assertions = [
      (specLib.portRegistryAssertion config.my.ports)
      (specLib.specPortAssertion config.my.services.spec)
      {
        assertion =
          !(config.services.caddy.enable or false) || (config.my.ingress.fromSpec.enable or false);
        message =
          "[SERVICES-SPEC] Caddy aktiv ohne fromSpec — alle vHosts müssen aus my.services.spec kommen.";
      }
      {
        assertion =
          let
            offenders =
              lib.filterAttrs (
                name: entry:
                let
                  expected = dnsMap.mapping.${name} or null;
                  sub = entry.subdomain or null;
                in
                expected != null && sub != null && expected != "${sub}.${domain}"
              ) config.my.services.spec;
          in
          offenders == { };
        message =
          let
            names = lib.attrNames (
              lib.filterAttrs (
                name: _:
                let
                  e = config.my.services.spec.${name};
                in
                (dnsMap.mapping.${name} or null) != null && (e.subdomain or null) != null
              ) config.my.services.spec
            );
            mismatches = lib.concatMapStringsSep "; " (
              name:
              let
                e = config.my.services.spec.${name};
              in
              "${name}: spec=${e.subdomain}.${domain} dns-map=${dnsMap.mapping.${name}}"
            ) (
              lib.filter (
                name:
                let
                  e = config.my.services.spec.${name};
                in
                (dnsMap.mapping.${name} or null) != "${e.subdomain}.${domain}"
              ) names
            );
          in
          "[SERVICES-SPEC] subdomain weicht von dns-map ab: ${mismatches}";
      }
    ];
  };
}