# ---
# schema: "109x=Infrastruktur-Band (kein Service-Port)"
# meta:
#   layer: 3
#   role: module
#   purpose: mDNS/Avahi — Host als <hostName>.local im LAN erreichbar, ohne DNS-Server
#   docs:
#     - docs/adr/1001-dns-dot-fail-closed.md
#   tags:
#     - dns
#     - mdns
#     - network
# ---
# Zweck: ssh jarvis@q958.local ohne IP, ohne Router-Eintrag, ohne DNS-Server.
#
# Optionsnamen gegen nixpkgs 26.05 verifiziert (2026-07-19):
#   nssmdns  ist umbenannt -> nssmdns4 / nssmdns6 (mkRenamedOptionModule)
#   publish.addresses, openFirewall existieren wie hier verwendet.
#
# ABGRENZUNG zu systemd-resolved (ADR-1001, DoT fail-closed):
#   resolved macht Unicast-DNS verschluesselt nach aussen. Avahi macht Multicast
#   im LAN. Die beiden stoeren sich nicht -- SOLANGE resolved nicht ZUSAETZLICH
#   MulticastDNS=yes bekommt. Zwei mDNS-Responder auf einem Host antworten sonst
#   beide und liefern wechselnde Ergebnisse. Also: mDNS hier, nicht in resolved.
#
# ABGRENZUNG zu 50-media (mediNix):
#   Das Media-Modul publiziert zusaetzlich {service}.local fuer die Dienste.
#   Es nutzt denselben Avahi -- deshalb hier die Basis, dort die Service-Aliase.
#
# .local ist AUSSCHLIESSLICH Multicast im LAN (RFC 6762):
#   nie in Cloudflare, nie als Unicast-Rewrite, kein Let's-Encrypt-Zertifikat.
#   Und: mDNS ist Layer-2-Multicast, laeuft also NICHT durch einen WireGuard-
#   Tunnel. Von unterwegs weiterhin ueber die Domain oder VPN-IP.
{ lib, config, ... }:
let
  cfg = config.my.services.mdns or { };
in
{
  options.my.services.mdns = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Host per mDNS als <networking.hostName>.local im LAN veroeffentlichen.

        Default an: Der Nutzen (Rechner ohne IP-Kenntnis erreichbar, ueberlebt
        DHCP-Wechsel) ist gross, die Angriffsflaeche minimal -- mDNS verlaesst
        das physische Netz nicht.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.avahi = {
      enable = true;

      # NSS-Integration: damit loest auch DIESER Host .local-Namen auf,
      # nicht nur andere Geraete ihn. Nuetzlich fuer Dienste, die sich
      # gegenseitig ueber .local ansprechen.
      nssmdns4 = true;
      nssmdns6 = false; # ADR-1002: Homelab ist v4-only

      # UDP 5353 -- ohne das antwortet Avahi nicht nach aussen.
      openFirewall = true;

      publish = {
        enable = true;
        # Der eigentliche Zweck: <hostName>.local -> aktuelle LAN-IP
        addresses = true;
        # Kein Werbe-Rauschen: wir wollen erreichbar sein, nicht im
        # Netzwerk-Browser als "Arbeitsplatz" auftauchen.
        workstation = false;
        hinfo = false;
        domain = false;
      };
    };
  };
}
