---
meta:
  role: doc
  purpose: ADR-009 VPN-NetNS-Leak-Check per systemd-Timer
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-media-stack.md
  tags:
    - adr
    - vpn
    - netns
---

# ADR-009: VPN-NetNS-Leak-Check

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Quelle** | nix-hermes ADR-10-VPN (Synthese) |

## Kontext

SABnzbd und Prowlarr laufen in einem dedizierten Network-Namespace mit WireGuard-Kill-Switch. Fällt der Tunnel trotzdem aus oder routet falsch, könnte Egress über die Host-ISP-IP laufen — ein Datenschutz- und Compliance-Risiko.

## Entscheidung

1. **`vpn-leak-check.service`** (oneshot): vergleicht öffentliche IP von Host und NetNS (`ipinfo.io`).
2. Bei Gleichheit: **Notstopp** von `sabnzbd` und `prowlarr`, Exit-Code 1.
3. **`vpn-leak-check.timer`**: Standard `*:0/15` (alle 15 Minuten), `RandomizedDelaySec = 2m`.
4. Aktivierung nur über **`machines/q958/rollout.nix`** (`leakCheck.enable`, ab Stufe 6).
5. Implementierung: `modules/10-vpn-confinement.nix` — Timer in `systemd.timers`, nicht in `systemd.services`.

## Konsequenzen

- Falsch-Positive möglich, wenn beide Probes fehlschlagen → Service überspringt (exit 0).
- Manuelle Prüfung: `systemctl start vpn-netns-test` (wenn `vpnTest.enable`).
- Prowlarr-API aus Sonarr/Radarr nutzt veth-Bridge (`192.168.15.0/24`), nicht Host-WAN.

## Nicht übernommen

- Systemweite VPN-Routing-Alternative (nix-hermes Option 2).
- Recyclarr / externe Flake-Inputs.