# ---
# meta:
#   layer: 3
#   role: module
#   purpose: nftables L4 — checkRuleset, WAN-Härtung, skuid, CrowdSec/Fail2ban
#   docs:
#     - docs/adr/2008-nftables-l4-hardening.md
#     - docs/guides/GUIDE-nftables-hardening.md
#   lib:
#     - lib/nftables-rules.nix
#   services:
#     - nftables
#   tags:
#     - firewall
#     - nftables
# ---
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.security.firewall;
  asserts = import ../../lib/assertions.nix { inherit lib; };
  ruleset = import ../../lib/nftables-rules.nix { inherit lib config; };

  optionalCountryZones = {
    at = ./geoip-at.zone;
    lt = ./geoip-lt.zone;
  };

  activeOptionalCountries = lib.filter (c: lib.hasAttr c optionalCountryZones) cfg.allowedCountries;

  mkGeoipNft =
    {
      country,
      zoneFile,
      flushSet ? false,
    }:
    pkgs.runCommand "geoip-${country}.nft"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.gnused
        ];
      }
      ''
        {
          ${lib.optionalString flushSet "echo 'flush set inet filter geoip_allowed'"}
          echo 'add element inet filter geoip_allowed {'
          grep -vE '^\s*(#|$)' ${zoneFile} | sed 's/$/,/' | sed '$ s/,$//' | sed 's/^/  /'
          echo '}'
        } > $out
      '';

  geoipDeNft = mkGeoipNft {
    country = "de";
    zoneFile = ./geoip-de.zone;
    flushSet = true;
  };

  geoipOptionalNft =
    country:
    mkGeoipNft {
      inherit country;
      zoneFile = optionalCountryZones.${country};
    };

  mkGeoipService =
    {
      description,
      nftFile,
      after ? [ "nftables.service" ],
      requires ? [ "nftables.service" ],
    }:
    {
      inherit description after requires;
      partOf = [ "nftables.service" ];
      wantedBy = [ "nftables.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.nftables}/bin/nft -f ${nftFile}";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
      };
    };
in
{
  options.my.security.firewall = {
    enable = lib.mkEnableOption "nftables L4 firewall (ersetzt networking.firewall)";

    lanCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
      description = "Vertrauenswürdige LAN-CIDRs — vor Geo-Block akzeptiert.";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Physisches LAN-Interface (z. B. eno1). Leer = Single-NIC ohne iifname-Check.";
    };

    wanInterface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "WAN-Interface für Bogon-Drop. Leer = Homelab Single-NIC (nur Loopback/Link-Local).";
    };

    allowedCountries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Optional: zusätzliche Länder aus vendorten Zone-Files im Nix-Store (ISO-2: "at", "lt").
        DE ist immer deklarativ geladen — kein Eintrag nötig.
        Aktualisierung: geoip-*.zone im Repo bumpen und rebuilden (kein Runtime-Fetch).
      '';
    };

    allowLanDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "UDP/TCP 53 von LAN an lokalen DNS-Server erlauben.";
    };

    blockCleartextDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Port 53 (unverschlüsseltes DNS) outbound sperren — nur DoT via systemd-resolved erlaubt. Loopback (127.0.0.0/8) bleibt offen für Blocky.";
    };

    webRateLimit = lib.mkOption {
      type = lib.types.str;
      default = "100/minute";
      description = "Neue HTTP/HTTPS-Verbindungen pro Quell-IP (WAN).";
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "IPv6-Input-Regeln (CrowdSec v6). false wenn LAN nur v4 (Netbird bleibt über iifname wt0).";
    };

    netbirdNotrack = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "raw-Table NOTRACK für wt0 (Netbird) — weniger conntrack-CPU.";
    };

    skuidSegmentation = {
      enable = lib.mkEnableOption "meta skuid Micro-Segmentation (UID-Registry, Stufe 8+)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.enable = false;

    networking.nftables = {
      enable = true;
      checkRuleset = true;
      inherit ruleset;
    };

    assertions = [
      (asserts.mkAssert {
        code = "FIREWALL-001";
        was = "my.security.firewall.lanCidrs ist leer — kein vertrauenswürdiges Netz definiert";
        warum = "LAN-CIDRs definieren in nftables welche IPs als 'intern' gelten. Ohne sie haben LAN-Only-Dienste (Grafana, Home Assistant, Proxmox) keine Zugriffsbeschränkung auf private IPs.";
        beheben = "my.security.firewall.lanCidrs = [\"192.168.x.0/24\"]; — eigenes LAN-Subnetz eintragen. Mehrere CIDRs (LAN + IoT-VLAN) als Liste möglich.";
        assertion = cfg.lanCidrs != [ ];
      })
      (asserts.mkAssert {
        code = "FIREWALL-002";
        was = "my.security.firewall.webRateLimit ist leer — kein Rate-Limit für eingehende HTTP/S-Verbindungen";
        warum = "Ohne Rate-Limit sind Port 443/80 unbegrenzt offen — auch für Connection-Floods. Das Rate-Limit ist die erste Verteidigungslinie vor Caddy/CrowdSec.";
        beheben = "my.security.firewall.webRateLimit = \"40/minute\"; — Wert je nach erwartetem Traffic anpassen.";
        assertion = cfg.webRateLimit != "";
      })
      (asserts.mkAssert {
        code = "FIREWALL-003";
        was = "my.security.firewall.skuidSegmentation ist aktiv, aber 'prowlarr' fehlt in my.users.registry";
        warum = "Netzwerk-Segmentierung nach UID erfordert vollständige UID-Registry aller Media-Dienste. Fehlt prowlarr, gilt die nftables skuid-Regel nicht → Segmentierung ist wirkungslos.";
        beheben = "my.users.registry.prowlarr = { uid = <uid>; gid = <gid>; }; ergänzen — oder skuidSegmentation deaktivieren.";
        umgehung = "my.security.firewall.skuidSegmentation.enable = false; bis Registry vollständig ist.";
        assertion = !(cfg.skuidSegmentation.enable && !config.my.users.registry ? prowlarr);
      })
      {
        assertion = lib.all (c: lib.hasAttr c optionalCountryZones) cfg.allowedCountries;
        message = ''
          FIREWALL-004: Unbekannte allowedCountries — nur vendorte Zonen verfügbar: ${lib.concatStringsSep ", " (lib.attrNames optionalCountryZones)}.
          Eintrag in my.security.firewall.allowedCountries prüfen oder geoip-<cc>.zone ergänzen.
        '';
      }
    ];

    systemd.services = {
      nftables-geoip-de = mkGeoipService {
        description = "GeoIP DE-Basis aus Nix-Store laden (kein Netz)";
        nftFile = geoipDeNft;
      };
    }
    // lib.genAttrs (map (c: "nftables-geoip-${c}") activeOptionalCountries) (
      name:
      let
        country = lib.removePrefix "nftables-geoip-" name;
      in
      mkGeoipService {
        description = "GeoIP ${lib.toUpper country} aus Nix-Store nachladen (kein Netz)";
        nftFile = geoipOptionalNft country;
        after = [
          "nftables.service"
          "nftables-geoip-de.service"
        ];
        requires = [
          "nftables.service"
          "nftables-geoip-de.service"
        ];
      }
    );
  };
}
