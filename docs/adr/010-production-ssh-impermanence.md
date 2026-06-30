---
meta:
  role: doc
  purpose: ADR-010 Production-Modus — SSH-Port, PermitTTY, Impermanence ab Rollout-Stufe 9
  status: accepted
  date: 2026-06-17
  betrifft:
    - machines/q958/profile.nix
    - machines/q958/rollout.nix
    - modules/20-security/ssh.nix
    - modules/30-storage/impermanence.nix
  docs:
    - docs/adr/README.md
    - docs/guides/GUIDE-security-secrets.md
    - docs/adr/006-sops-migration-path.md
    - docs/adr/008-nftables-l4-hardening.md
  tags:
    - adr
    - ssh
    - impermanence
    - production
    - rollout
---

# ADR-010: Production-Modus — SSH, TTY, Impermanence {#adr-010}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |
| **Quelle** | nix-hermes ADR-24 (Synthese) |

## Kontext {#kontext}

Während der Entwicklung (Stufe < 9) bleibt SSH auf Port 22 und der Root ist tmpfs-freundlich. In Production (Stufe ≥ 9) gelten Zero-Trust-Defaults: kein Passwort-Login, gehärteter Port, ephemeres `/`.

SOPS für Secrets-Management ([ADR-006](006-sops-migration-path.md)) wird ebenfalls erst in Stufe 9+ aktiviert. nftables ([ADR-008](008-nftables-l4-hardening.md)) liest `my.ports.ssh` — kein separates Port-Mapping in der Firewall.

## Entscheidung {#entscheidung}

1. **`rollout.stufe >= 9`** setzt `my.mode = "production"` und aktiviert `my.impermanence`.
2. **SSH-Port** wechselt über `rollout.nix`: `my.ports.ssh = productionSshPort` (q958: **53844**, Daten in `machines/q958/profile.nix`).
3. **`PermitTTY`**: Match für LAN/Tailscale-CIDR → `yes`; Match All → `no` (`modules/20-security/ssh.nix`).
4. **nftables** liest `my.ports.ssh` — kein separates Port-Mapping in der Firewall ([ADR-008](008-nftables-l4-hardening.md)).
5. **Dropbear-Rescue** bleibt unabhängig vom Modus aktiv (Stufe 8+).

### Rollout-Stufenplan {#stufenplan}

| Stufe | Was ändert sich |
|-------|----------------|
| < 9 | SSH Port 22, kein Impermanence, `profile.local.nix` für Secrets |
| = 9 | SSH Port 53844, Impermanence aktiv, SOPS für Secrets |

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Zero-Trust-SSH ab Stufe 9: kein Passwort, nicht-standardisierter Port, TTY nur von vertrautem Netz.
- Impermanence: Tier-A-Pfade via bind-mount aus `/persist` — System startet immer sauber.

### Negativ {#negativ}

- Vor Stufe-9-Sprung: SSH-Keys und `productionSshPort` in Client-Config eintragen.
- Impermanence: Tier-A-Pfade werden per bind-mount aus `/persist` geholt (`modules/30-storage/impermanence.nix` + `tmpfiles.rules`).
- Entwicklung: `networking.firewall.allowedTCPPorts` erlaubt Port 22 bis Stufe 8.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Rollout-Stufen | `machines/q958/rollout.nix` |
| SSH-Härtung | `modules/20-security/ssh.nix` |
| Impermanence | `modules/30-storage/impermanence.nix` |
| Production-Port | `machines/q958/profile.nix` → `productionSshPort` |

## Alternativen verworfen {#alternativen}

- **mTLS-Fortress statt Tailscale** — zu komplex für Single-Host-Homelab. Abgelehnt; Tailscale bleibt Gleis-2.
- **Manuelles Umschalten einzelner `.enable`-Flags** ohne Rollout-Stufe — nicht deterministisch, keine klare Grenze Dev/Prod. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-006 — SOPS-Migration](006-sops-migration-path.md) — Secrets-Management das gleichzeitig mit Stufe 9 aktiviert wird
- [ADR-008 — nftables L4-Härtung](008-nftables-l4-hardening.md) — Firewall liest `my.ports.ssh` dynamisch
- [GUIDE-security-secrets](../guides/GUIDE-security-secrets.md) — ausführliche Anleitung zur Secrets-Verwaltung
