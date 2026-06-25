# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: DNS-Upstream-Verschlüsselungs-Assertions (DoT/DoH)
#   docs:
#     - docs/adr/001-dns-dot-fail-closed.md
#     - docs/AUDIT-blocky-caddy-ipv6.md
#   tags:
#     - dns
#     - dot
# ---
{ lib, ... }:

let
  encryptedPrefixes = [
    "tcp-tls:"
    "https://"
    "quic:"
    "sdns://"
  ];

  isEncryptedUpstream = entry:
    lib.any (prefix: lib.hasPrefix prefix entry) encryptedPrefixes;

  isPlaintextUpstream = entry:
    !isEncryptedUpstream entry
    && (
      builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+(:[0-9]+)?$" entry != null
      || lib.hasPrefix "tcp+udp:" entry
      || lib.hasPrefix "udp:" entry
      || (lib.hasPrefix "tcp:" entry && !lib.hasPrefix "tcp-tls:" entry)
    );

  allEncrypted = entries: lib.all isEncryptedUpstream entries;

  nonePlaintext = entries: lib.all (e: !isPlaintextUpstream e) entries;
in
{
  inherit isEncryptedUpstream isPlaintextUpstream allEncrypted nonePlaintext;
}