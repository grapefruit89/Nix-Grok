---
title: ADR-041-Dendritic-Firewall
status: accepted
date: 2026-06-19
tags:
  - adr
  - firewall
  - security
  - dendritic
---

# ADR 041: Dendritic Firewall Pattern

## 1. Kontext
NixOS bietet die Möglichkeit, die Firewall über das veraltete Legacy-`iptables`-Backend (`networking.firewall.enable`) oder direkt über pure `nftables`-Konfigurationen (`networking.nftables.enable`) zu betreiben.
Historisch wurde das komplette nftables-Regelwerk in einer einzigen großen Zeichenkette in `modules/15-firewall.nix` deklariert. Dies verhinderte, dass einzelne App-Module (z.B. Matrix, Gatus) ihre benötigten Ports selbstständig in ihren eigenen Moduldateien ("Dendritic Pattern") öffnen konnten.

## 2. Entscheidung
Wir etablieren das **Dendritic Firewall Pattern** über `networking.nftables.tables`.
- **Zentrale Absicherung:** In `15-firewall.nix` definieren wir die globalen Security-Regeln (GeoIP-Blocks, CrowdSec-Bouncer, SYN-Flood-Schutz) am Anfang der `input`-Chain mittels `lib.mkBefore`.
- **Der Hook:** Vor der abschließenden `drop`-Policy springt das Regelwerk mit `jump app_input` in eine separate Kette.
- **Modulare Injektion:** Jedes App-Modul deklariert bei Bedarf `networking.nftables.tables."filter".content = "chain app_input { tcp dport 8448 accept }"`.

## 3. Konsequenzen
**Positiv:**
- Vollständige Modularität. Apps bringen ihre eigenen Portfreigaben mit ("Ein Feature, eine Datei").
- Absolute Sicherheit: Die modularen App-Regeln können die globalen GeoIP- und CrowdSec-Bouncer **nicht** umgehen, da der `jump` erst nach den harten Security-Checks stattfindet.

**Negativ / Risiko:**
- Es erfordert Verständnis von `nftables`-Syntax in den App-Modulen statt der simplen Nutzung von `networking.firewall.allowedTCPPorts`. Da aber `allowedTCPPorts` an Legacy-iptables gebunden war, ist dies ein notwendiger Trade-off.
