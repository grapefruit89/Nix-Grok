---
meta:
  role: doc
  purpose: ADR-009 VPN-NetNS-Leak-Check per systemd-Timer — SABnzbd + Prowlarr Egress-Verifikation
  status: accepted
  date: 2026-06-17
  error_pattern: "vpn.leak.check.*failed|IP.*match.*host|sabnzbd.*stopped.*leak|prowlarr.*stopped.*leak"
  quick_fix: "systemctl status vpn-leak-check; ip -n vpn-netns addr show"
  services: [vpn-leak-check, sabnzbd, prowlarr]
  betrifft:
    - modules/10-network/vpn-confinement.nix
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-media-stack.md
    - docs/adr/008-nftables-l4-hardening.md
  tags:
    - adr
    - vpn
    - netns
    - sabnzbd
    - prowlarr
---

# ADR-009: VPN-NetNS-Leak-Check {#adr-009}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Quelle** | nix-hermes ADR-10-VPN (Synthese) |

## Kontext {#kontext}

SABnzbd und Prowlarr laufen in einem dedizierten Network-Namespace mit WireGuard-Kill-Switch. Fällt der Tunnel trotzdem aus oder routet falsch, könnte Egress über die Host-ISP-IP laufen — ein Datenschutz- und Compliance-Risiko.

Die nftables-Firewall ([ADR-008](008-nftables-l4-hardening.md)) schützt auf L4, erkennt aber keinen falschen Route im VPN-NetNS.

## Entscheidung {#entscheidung}

1. **`vpn-leak-check.service`** (oneshot): vergleicht öffentliche IP von Host und NetNS (`ipinfo.io`).
2. Bei Gleichheit: **Notstopp** von `sabnzbd` und `prowlarr`, Exit-Code 1.
3. **`vpn-leak-check.timer`**: Standard `*:0/15` (alle 15 Minuten), `RandomizedDelaySec = 2m`.
4. Aktivierung nur über **`machines/q958/rollout.nix`** (`leakCheck.enable`, ab Stufe 6).
5. Implementierung: `modules/10-network/vpn-confinement.nix` — Timer in `systemd.timers`, nicht in `systemd.services`.

## Diagnose {#diagnose}

**Symptom:** SABnzbd/Prowlarr gestoppt ohne erkennbaren Grund, oder Leak-Check meldet Fehler.

```bash
# Leak-Check-Status
systemctl status vpn-leak-check --no-pager
journalctl -u vpn-leak-check -n 20 --no-pager

# VPN-NetNS-IP prüfen (muss VPN-IP, nicht Host-IP sein)
ip -n vpn-netns addr show
# Host-IP zum Vergleich
curl -s https://ipinfo.io/ip

# Manueller Leak-Test
systemctl start vpn-netns-test
```

## Fix {#fix}

```bash
# 1. VPN-Tunnel-Status prüfen
ip -n vpn-netns route show
systemctl status wg-netns --no-pager 2>/dev/null

# 2. VPN neu starten
sudo systemctl restart wg-netns 2>/dev/null || sudo systemctl restart vpn-confinement

# 3. Dienste manuell neu starten wenn VPN wieder läuft
sudo systemctl start sabnzbd prowlarr

# 4. Leak-Check manuell ausführen (Verifikation)
sudo systemctl start vpn-leak-check
systemctl status vpn-leak-check --no-pager
```

## Konsequenzen {#konsequenzen}

- Falsch-Positive möglich, wenn beide Probes fehlschlagen → Service überspringt (exit 0).
- Manuelle Prüfung: `systemctl start vpn-netns-test` (wenn `vpnTest.enable`).
- Prowlarr-API aus Sonarr/Radarr nutzt veth-Bridge (`192.168.15.0/24`), nicht Host-WAN.

## Alternativen verworfen {#alternativen}

- **Systemweite VPN-Routing-Alternative** (nix-hermes Option 2) — würde alle Dienste durch VPN zwingen; nicht gewollt für Homelab. Abgelehnt.
- **Recyclarr / externe Flake-Inputs** — außerhalb Scope dieses ADR; keine externen Flake-Inputs ([ADR-013](013-flake-portability.md)).
- **Nur nftables-Egress-Regeln** ([ADR-008](008-nftables-l4-hardening.md)) — erkennen keinen falschen Route-Leak im NetNS. Nicht ausreichend alleine.

## Siehe auch {#siehe-auch}

- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — Egress-Regeln die VPN-NetNS ergänzen
- [GUIDE-media-stack](../guides/GUIDE-media-stack.md) — SABnzbd/Prowlarr im VPN-NetNS-Kontext
