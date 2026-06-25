---
meta:
  role: doc
  purpose: ADR-010 Production-Modus — SSH-Port, PermitTTY, Impermanence
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-security-secrets.md
  tags:
    - adr
    - ssh
    - impermanence
---

# ADR-010: Production-Modus — SSH, TTY, Impermanence

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Quelle** | nix-hermes ADR-24 (Synthese) |

## Kontext

Während der Entwicklung (Stufe &lt; 9) bleibt SSH auf Port 22 und der Root ist tmpfs-freundlich. In Production (Stufe ≥ 9) gelten Zero-Trust-Defaults: kein Passwort-Login, gehärteter Port, ephemeres `/`.

## Entscheidung

1. **`rollout.stufe >= 9`** setzt `my.mode = "production"` und aktiviert `my.impermanence`.
2. **SSH-Port** wechselt über `rollout.nix`: `my.ports.ssh = productionSshPort` (q958: **53844**, Daten in `machines/q958/profile.nix`).
3. **`PermitTTY`**: Match für LAN/Tailscale-CIDR → `yes`; Match All → `no` (`modules/20-security.nix`).
4. **nftables** liest `my.ports.ssh` — kein separates Port-Mapping in der Firewall.
5. **Dropbear-Rescue** bleibt unabhängig vom Modus aktiv (Stufe 8+).

## Konsequenzen

- Vor Stufe-9-Sprung: SSH-Keys und `productionSshPort` in Client-Config eintragen.
- Impermanence: Tier-A-Pfade werden per bind-mount aus `/persist` geholt (`modules/30-storage.nix` + `tmpfiles.rules`).
- Entwicklung: `networking.firewall.allowedTCPPorts` erlaubt Port 22 bis Stufe 8.

## Nicht übernommen

- mTLS-Fortress statt Tailscale (Gleis-2 bleibt Tailscale).
- Manuelles Umschalten einzelner `.enable`-Flags pro Modul ohne Rollout-Stufe.