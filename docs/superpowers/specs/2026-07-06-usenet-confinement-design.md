---
name: usenet-confinement-modernisierung
description: Design-Spec für die Ablösung der POSIX-NetNS-Lösung durch einen modernen host-basierten UID-Sandbox-Stack für SABnzbd + Prowlarr
metadata:
  type: project
---

# Design: Usenet-Confinement Modernisierung

**Datum:** 2026-07-06
**Status:** approved
**Ziel:** POSIX-Network-Namespace-Infrastruktur restlos entfernen, durch modernen host-basierten Stack ersetzen.

---

## Kontext

Die alte `12-vpn-confinement.nix` implementierte VPN-Isolation via POSIX-Network-Namespaces (netns),
veth-Bridges und manuelle WireGuard-Konfiguration. Dieser Ansatz war:

- Imperativer Shell-Code (ip/wg/nft-Befehle) statt deklarativer Nix-Config
- Schwer wartbar, schwer debugbar
- Unnötig komplex: `lib/vpn-connection.nix` löste zur Laufzeit immer zu `127.0.0.1` auf
- Dead code: `vpn-confinement.enable` war nie auf `true` gesetzt

Der modernere Ansatz (`1096-vpn.nix` UID-Routing + `RestrictNetworkInterfaces`) war bereits aktiv,
aber nicht vollständig implementiert (fehlende DNS-Isolation, legacy nftables-Regeln).

---

## Entscheidung

**Atomic-Ansatz:** Neues Modul + alle Importe entfernen + alte Dateien löschen = ein Commit + ein rebuild.

Grund: Nix eval bricht wenn Dateien fehlen aber noch importiert werden. Da die alte Infrastruktur
bereits dead code ist, gibt es kein Risiko.

---

## Architektur: Defense-in-Depth (3 Schichten)

```
SABnzbd / Prowlarr (UID 5007 / 5006)
         │
         ▼
┌─────────────────────────────────────────┐
│ Schicht 1: systemd (BPF-Level)          │
│  RestrictNetworkInterfaces=[lo privado] │
│  BindReadOnlyPaths (resolv.conf)        │
│  PrivateIPC, RestrictNamespaces, etc.   │
└─────────────┬───────────────────────────┘
              │ nur lo + privado Pakete kommen durch
              ▼
┌─────────────────────────────────────────┐
│ Schicht 2: nftables (Paket-Level)       │
│  skuid { 5006, 5007 }                   │
│  oifname != { "lo", "privado" } drop    │
└─────────────┬───────────────────────────┘
              │ Egress nur via privado
              ▼
┌─────────────────────────────────────────┐
│ Schicht 3: UID-Routing (ip rule)        │
│  uidrange 5006-5006 lookup 51820        │
│  uidrange 5007-5007 lookup 51820        │
│  default route → privado WireGuard      │
└─────────────────────────────────────────┘
              │
              ▼
         Privado VPN
```

---

## Was wird gelöscht

| Datei | Grund |
|---|---|
| `modules/10-network/12-vpn-confinement.nix` | Dead code — never active |
| `lib/vpn-killswitch.nix` | Ersetzt durch 57-usenet-confinement |
| `lib/vpn-connection.nix` | Reine netns-Abstraktion, löste immer zu 127.0.0.1 auf |

---

## Was wird geändert

### `modules/10-network/default.nix`
- Import `./12-vpn-confinement.nix` entfernen

### `machines/q958/default.nix`
- Ganzen `services.vpn-confinement` Block entfernen

### `modules/50-media/default.nix`
- Import `./57-usenet-confinement` hinzufügen

### `machines/q958/rollout.nix`
- `privado-vpn.enable = erstAb 6;` bleibt (Routing-Basis)
- `my.services.usenet-confinement.enable = erstAb 6;` neu hinzufügen

### `modules/50-media/52-arr.nix`
- `vpnConn` import + alle `vpnConn.*`-Aufrufe entfernen
- `prowlarr.upstreamHost`: fix auf `"127.0.0.1"`

### `modules/50-media/53-sabnzbd.nix`
- `vpnConn`, `vpnKillSwitch`, `sabInVpn` entfernen
- `host`: fix auf `"127.0.0.1"` (war schon immer so)
- `lib.mkIf (!(vpn-confinement.enable))` Guards entfernen

### `modules/50-media/arr-helper.nix`
- `vpnKillSwitchAttrs` import entfernen
- `useVpnKillSwitch` Option + Guard-Block entfernen

### `lib/nftables-rules.nix`
- `vpnBridgeAccepts` Block entfernen (referenziert vpn-confinement)
- `skuidUsenetGuard` Positivliste:
  ```
  # Neu:
  meta skuid { 5006, 5007 } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress"
  ```

---

## Neues Modul: `modules/50-media/57-usenet-confinement/default.nix`

Inhalt (Pseudocode / Orientierung — exakte Implementierung im Writing-Plan):

```nix
options.my.services.usenet-confinement.enable = mkEnableOption "Usenet VPN-Sandbox (SABnzbd + Prowlarr via Privado WireGuard)";

config = mkIf cfg.enable {
  # DNS-Datei aus privado.dns generieren
  environment.etc."usenet-resolv.conf".text =
    concatMapStrings (dns: "nameserver ${dns}\n") privado.dns;

  # Sandbox auf beide Services anwenden
  systemd.services.sabnzbd = sandboxAttrs;
  systemd.services.prowlarr = sandboxAttrs;
};

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
```

### Eigenschaften

| Attribut | Wirkung |
|---|---|
| `BindsTo` auf privado.device | Service stoppt wenn WireGuard down |
| `RestrictNetworkInterfaces` | BPF — kein Socket außer lo/privado möglich |
| `BindReadOnlyPaths` | Überschattet /etc/resolv.conf → nur VPN-DNS sichtbar |
| `PrivateIPC` | Kein SysV/POSIX IPC |
| `RestrictNamespaces` | Kein `unshare`/`clone` mit Namespace-Flags |
| `ProcSubset=pid` | /proc zeigt nur eigene PIDs |
| `InaccessiblePaths=/sys/class/net` | Kein Interface-Listing |

---

## DNS-Hinweis: cleartextDnsBlock

Falls `my.security.firewall.blockCleartextDns = true` künftig aktiviert wird: Die usenet-Dienste
senden DNS an 198.18.0.1 via privado. Diese Regel würde das abfangen. In diesem Fall braucht
`skuidUsenetGuard` eine DNS-Ausnahme für privado. Umgesetzt in `lib/nftables-rules.nix` (`skuidUsenetDnsAllow`).

---

## Verifikation nach Rebuild

```bash
# Sandbox-Attribute gesetzt?
systemctl show sabnzbd -p RestrictNetworkInterfaces,BindsTo,PrivateIPC
systemctl show prowlarr -p RestrictNetworkInterfaces,BindsTo,PrivateIPC

# DNS-Isolation korrekt?
cat /etc/usenet-resolv.conf
# Erwartet: nameserver 198.18.0.1 / nameserver 198.18.0.2

# nftables sauber?
nft list ruleset | grep "usenet VPN-only"

# Kein Legacy mehr?
grep -r "vpn.confinement\|vpn_confinement\|netns\|veth.usenet\|usenet.br" /etc/nixos/ 2>/dev/null
# Erwartet: keine Treffer
```

---

## ADR

Entscheidung dokumentiert in: `docs/adr/5031-usenet-vpn-sandbox.md`
Supersedes: `docs/adr/2009-vpn-leak-check.md`
Ergänzt: `docs/adr/2008-nftables-l4-hardening.md`
