---
meta:
  role: doc
  purpose: ADR-5031 Usenet-Dienste VPN-Sandbox — Ablösung POSIX-NetNS durch host-basierten UID-Stack
  status: accepted
  date: 2026-07-06
  error_pattern: "sabnzbd.*network.*denied|prowlarr.*network.*denied|privado.*not found|sys-subsystem-net-devices-privado.*failed"
  quick_fix: "systemctl status wg-quick-privado; systemctl show sabnzbd -p RestrictNetworkInterfaces"
  services: [sabnzbd, prowlarr, wg-quick-privado]
  betrifft:
    - modules/50-media/57-usenet-confinement/default.nix
    - lib/nftables-rules.nix
    - modules/50-media/52-arr.nix
    - modules/50-media/53-sabnzbd.nix
    - modules/50-media/arr-helper.nix
  docs:
    - docs/adr/README.md
    - docs/adr/2008-nftables-l4-hardening.md
    - docs/adr/2009-vpn-leak-check.md
    - docs/adr/011-unified-port-uid-schema.md
    - docs/adr/028-systemd-service-isolation.md
    - docs/superpowers/specs/2026-07-06-usenet-confinement-design.md
  tags:
    - adr
    - vpn
    - usenet
    - sabnzbd
    - prowlarr
    - systemd
    - nftables
    - security
---

# ADR-5031: Usenet-Dienste VPN-Sandbox (host-basiert) {#adr-5031}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-06 |
| **Host** | q958 |
| **Supersedes** | [ADR-2009 — VPN-NetNS-Leak-Check](2009-vpn-leak-check.md) |

---

## Kontext {#kontext}

- SABnzbd + Prowlarr müssen ihren gesamten Netzwerkverkehr über das Privado WireGuard-Interface leiten
- Die alte Lösung (`12-vpn-confinement.nix`) nutzte POSIX-Network-Namespaces (netns), veth-Bridges und imperativem Shell-Code
- `vpn-confinement.enable` war nie auf `true` gesetzt — die Infrastruktur war dead code
- `lib/vpn-connection.nix` löste zur Laufzeit immer zu `127.0.0.1` auf (netns-Abstraktion ohne Funktion)
- Das moderne UID-basierte Routing (`16-vpn.nix`, `RestrictNetworkInterfaces`) war bereits aktiv, aber unvollständig (kein DNS-Leak-Schutz, legacy nftables)

## Entscheidung {#entscheidung}

**Vollständige Ablösung der POSIX-NetNS-Infrastruktur durch einen host-basierten UID-Sandbox-Stack in `57-usenet-confinement/`.**

Die neue Lösung nutzt drei komplementäre Schichten:

### Schicht 1: systemd (BPF-Level) {#systemd-layer}

```nix
# modules/50-media/57-usenet-confinement/default.nix {#modules50-media57-usenet-confinementdefaultnix}
sandboxAttrs = {
  bindsTo = [ "sys-subsystem-net-devices-privado.device" ];
  after   = [ "sys-subsystem-net-devices-privado.device" ];
  serviceConfig = {
    RestrictNetworkInterfaces = [ "lo" "privado" ];
    BindReadOnlyPaths         = [ "/etc/usenet-resolv.conf:/etc/resolv.conf" ];
    PrivateIPC                = true;
    RestrictNamespaces        = true;
    ProcSubset                = "pid";
    InaccessiblePaths         = [ "/sys/class/net" ];
  };
};
```text

`RestrictNetworkInterfaces` greift am BPF-Level — Sockets die andere Interfaces versuchen werden vom Kernel geblockt, bevor ein Paket entsteht. Kein Bypass über nftables-Lücken möglich.

### Schicht 2: nftables (Paket-Level) {#nftables-layer}

```
# lib/nftables-rules.nix — skuidUsenetGuard {#libnftables-rulesnix-skuidusenetguard}
meta skuid { 5006, 5007 } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress"
```text

Positive Whitelist statt Negativliste. Entfernt alle Legacy-Referenzen (`veth-usenet`, `usenet-br`, `192.168.15.0/24`).

### Schicht 3: UID-Routing (Policy Routing) {#routing-layer}

```bash
# 16-vpn.nix (postUp) {#16-vpnnix-postup}
ip rule add uidrange 5006-5006 lookup 51820 priority 95006
ip rule add uidrange 5007-5007 lookup 51820 priority 95007
ip route add default dev privado table 51820
```

Bereits aktiv — bleibt unverändert.

### DNS-Isolation {#dns-isolation}

```nix
environment.etc."usenet-resolv.conf".text =
  lib.concatMapStrings (dns: "nameserver ${dns}\n") config.my.services.privado-vpn.dns;
```bash

Generiert zur Build-Zeit aus `my.services.privado-vpn.dns`. Per `BindReadOnlyPaths` wird `/etc/resolv.conf` für die Usenet-Prozesse durch diese Datei überschattet. Effekt: nur Privado-DNS (198.18.0.1 / 198.18.0.2) erreichbar, kein DNS-Leak über Host-Resolver.

## Diagnose {#diagnose}

**Symptom:** sabnzbd/prowlarr starten nicht oder verlieren Netzwerk nach WireGuard-Neustart.

```bash
# Interface-Status {#interface-status}
systemctl status wg-quick-privado --no-pager

# Sandbox-Attribute prüfen {#sandbox-attribute-pruefen}
systemctl show sabnzbd -p RestrictNetworkInterfaces,BindsTo,PrivateIPC
systemctl show prowlarr -p RestrictNetworkInterfaces,BindsTo,PrivateIPC
```

**Erwarteter Output:**
```text
RestrictNetworkInterfaces=lo privado
BindsTo=sys-subsystem-net-devices-privado.device
PrivateIPC=yes
```

<details>
<summary>Vollständige Diagnose-Befehle (ausklappen)</summary>

```bash
# DNS-Isolation aktiv? {#dns-isolation-aktiv}
cat /etc/usenet-resolv.conf

# nftables Regel vorhanden? {#nftables-regel-vorhanden}
nft list ruleset | grep "usenet VPN-only"

# Routing korrekt? {#routing-korrekt}
ip rule list | grep "5006\|5007"
ip route show table 51820

# Kein Legacy mehr? {#kein-legacy-mehr}
grep -r "vpn.confinement\|veth.usenet\|usenet.br\|192\.168\.15\." /etc/nixos/ 2>/dev/null

# Journal {#journal}
journalctl -u sabnzbd -u prowlarr -n 30 --no-pager
```bash

</details>

## Fix {#fix}

```bash
# Schritt 1: WireGuard-Status prüfen {#schritt-1-wireguard-status-pruefen}
systemctl status wg-quick-privado --no-pager

# Schritt 2: Bei WireGuard-Problem {#schritt-2-bei-wireguard-problem}
systemctl restart wg-quick-privado

# Schritt 3: Services neu starten (starten automatisch wenn privado.device erscheint) {#schritt-3-services-neu-starten-starten-automatisch-wenn-privadodevice-erscheint}
systemctl start sabnzbd prowlarr

# Schritt 4: Dry-build nach Config-Änderungen {#schritt-4-dry-build-nach-config-aenderungen}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# Schritt 5: Verifikation {#schritt-5-verifikation}
systemctl show sabnzbd -p RestrictNetworkInterfaces,BindsTo
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Vollständig deklarativ — kein imperatives Shell-Skript mehr
- Defense-in-Depth: systemd BPF + nftables + UID-Routing (3 unabhängige Schichten)
- DNS-Leak-Schutz via `BindReadOnlyPaths` (war vorher komplett fehlend)
- Kill-Switch per `BindsTo`: Services stoppen sofort wenn VPN weg
- SSoT erhalten: alle Werte kommen aus `my.*` Options
- Wartbar: ein Modul statt drei verstreute Libs

### Negativ / Trade-offs {#negativ}


- **Schwächere Prozess-Isolation als POSIX-NetNS:** Ein echter Network-Namespace isoliert den Prozess auf Kernel-Ebene vollständig vom Host-Netzwerk-Stack. `RestrictNetworkInterfaces` arbeitet per BPF und blockiert Socket-Operationen auf unerlaubten Interfaces — ist aber kein vollständiger Namespace. Für Homelab-Threat-Model (kein adversarial Code) akzeptabel. Bei höherem Threat-Model: NetNS oder Container.
- `PrivateIPC` + `RestrictNamespaces` könnten mit ungewöhnlichen Plugin-Funktionen interferieren (bisher kein Problem bei SABnzbd/Prowlarr)
- DNS-Isolation via statische Datei: bei DNS-IP-Änderung von Privado braucht's `nixos-rebuild` (akzeptabel, da selten)
- Wenn `blockCleartextDns` künftig aktiviert wird: skuid-DNS-Ausnahme für DNS-Traffic via privado nötig

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Neues Modul | `modules/50-media/57-usenet-confinement/default.nix` |
| Gelöscht | `modules/10-network/12-vpn-confinement.nix` |
| Gelöscht | `lib/vpn-killswitch.nix` |
| Gelöscht | `lib/vpn-connection.nix` |
| Geändert | `lib/nftables-rules.nix` |
| Geändert | `modules/50-media/arr-helper.nix` |
| Geändert | `modules/50-media/52-arr.nix` |
| Geändert | `modules/50-media/53-sabnzbd.nix` |
| Geändert | `modules/50-media/default.nix` |
| Geändert | `machines/q958/default.nix` |
| Geändert | `machines/q958/rollout.nix` |

### Verifikation {#verifikation}

```bash
systemctl show sabnzbd -p RestrictNetworkInterfaces,BindsTo,PrivateIPC,ProcSubset
# RestrictNetworkInterfaces=lo privado {#restrictnetworkinterfaceslo-privado}
# BindsTo=sys-subsystem-net-devices-privado.device {#bindstosys-subsystem-net-devices-privadodevice}
# PrivateIPC=yes {#privateipcyes}
# ProcSubset=pid {#procsubsetpid}

nft list ruleset | grep "usenet VPN-only"
# meta skuid { 5006, 5007 } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress" {#meta-skuid-5006-5007-oifname-lo-privado-drop-comment-usenet-vpn-only-egress}
```text

## Alternativen verworfen {#alternativen}

- **POSIX Network Namespaces (12-vpn-confinement.nix)** — imperativ, komplex, nicht deklarativ, war bereits deaktiviert. Abgelehnt.
- **NixOS-Container** — würde SSoT (my.ports, my.services.spec, my.impermanence) zerstören. Abgelehnt.
- **systemd-resolved Stub für VPN-DNS** — unnötig komplex für statische DNS-IPs. Statische Datei reicht. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-06 | Initial — ersetzt ADR-2009 |

## Siehe auch {#siehe-auch}

- [ADR-2008 — nftables L4-Härtung](2008-nftables-l4-hardening.md) — skuid-Segmentierung die dieser ADR ergänzt
- [ADR-2009 — VPN-NetNS-Leak-Check](2009-vpn-leak-check.md) — superseded by this ADR
- [ADR-011 — UID-Schema](011-unified-port-uid-schema.md) — UID 5006/5007 für prowlarr/sabnzbd
- [ADR-028 — systemd Service Isolation](028-systemd-service-isolation.md) — Hardening-Grundlagen
- [Design-Spec](../superpowers/specs/2026-07-06-usenet-confinement-design.md) — vollständige Implementierungsdetails
