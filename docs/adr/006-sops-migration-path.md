---
meta:
  role: doc
  purpose: ADR-006 SOPS-Migration — Pfad von secrets-provision zu SOPS für Cloudflare-Token
  status: accepted
  date: 2026-06-17
  betrifft:
    - machines/q958/secrets.nix
    - machines/q958/profile.local.nix
    - modules/10-network/11-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/010-production-ssh-impermanence.md
  tags:
    - adr
    - sops
    - secrets
    - cloudflare
    - ddns
---

# ADR-006: SOPS-Migration — Pfad von secrets-provision {#adr-006}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext {#kontext}

- Heute: `machines/q958/secrets.nix` + `profile.local.nix` → `/var/lib/secrets` (Dev/Rollout < 9).
- mynixos nutzt SOPS + `dns-automation` mit `sops.secrets.cloudflare_token`.
- DDNS und DNS-Guard brauchen einen Cloudflare API-Token — noch **ohne** SOPS.
- AGENTS.md: SOPS erst ganz am Ende des Rollouts (Stufe 9+, [ADR-010](010-production-ssh-impermanence.md)).

## Entscheidung {#entscheidung}

1. **Jetzt (Stufe < 9):** Token in `profile.local.nix` → `q958-secrets-provision` schreibt:
   - `/var/lib/secrets/cloudflare_api_token`
   - `/var/lib/secrets/ddns-updater-config.json`
2. **DDNS:** `services.ddns-updater` (qdm12), kein Cloudflared-Tunnel — Fritzbox Port-Forward 80/443 + Caddy ACME.
3. **DNS-Guard:** optionaler Timer in `modules/10-network/11-network.nix`, liest dasselbe Token-File.
4. **Später (Stufe 9+):** SOPS ersetzt `profile.local`-Klartext; Provision-Script wird dünn oder entfällt.

### Migrationspfad {#migrationspfad}

```
Stufe < 9:  profile.local.nix → secrets-provision → /var/lib/secrets/*
Stufe 9+:   sops.secrets.cloudflare_token → /run/secrets/cloudflare_token
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Dynamische IP (Speedport) → Cloudflare A-Record ohne manuelles Dashboard.
- Kein Tunnel — direkter Caddy-Ingress bleibt Architektur-Kern.
- Migrationspfad dokumentiert; mynixos-Muster ohne `options.my.meta.*`.

### Negativ {#negativ}

- Token liegt bis SOPS in gitignored `profile.local.nix` — nicht auf anderen Hosts kopieren.
- HTTP-01 ACME braucht erreichbare Ports 80/443 am Router.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Gateway | `modules/10-network/11-network.nix` |
| Provision | `machines/q958/secrets.nix` |
| Registry | `NIXH-10-GTW-001` |

## Alternativen verworfen {#alternativen}

- **Cloudflared Tunnel** — ersetzt Caddy-Ingress, widerspricht q958-Design (Caddy als einziger Ingress). Abgelehnt.
- **Sofort SOPS** — zu früh im Rollout, erhöht Komplexität bevor System stabil läuft. Abgelehnt.
- **ClamAV** — offen; separates ADR wenn AV auf Gateway-Ebene gewünscht.

## Siehe auch {#siehe-auch}

- [ADR-010 — Production-Modus](010-production-ssh-impermanence.md) — Stufe 9+ wo SOPS aktiviert wird
- [GUIDE-security-secrets.md#secrets](../guides/GUIDE-security-secrets.md#secrets) — Secrets-Betrieb bis Stufe 9, SOPS-Migration
