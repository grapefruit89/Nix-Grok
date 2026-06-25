---
meta:
  role: doc
  purpose: ADR-006 SOPS-Migration vs. secrets-provision
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - sops
---

# ADR-006: SOPS-Migration — Pfad von secrets-provision

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-06-17 |
| **Host** | q958 |

## Kontext

- Heute: `machines/q958/secrets.nix` + `profile.local.nix` → `/var/lib/secrets` (Dev/Rollout < 9).
- mynixos nutzt SOPS + `dns-automation` mit `sops.secrets.cloudflare_token`.
- DDNS und DNS-Guard brauchen einen Cloudflare API-Token — noch **ohne** SOPS.
- AGENTS.md: SOPS erst ganz am Ende des Rollouts.

## Entscheidung

1. **Jetzt:** Token in `profile.local.nix` → `q958-secrets-provision` schreibt:
   - `/var/lib/secrets/cloudflare_api_token`
   - `/var/lib/secrets/ddns-updater-config.json`
2. **DDNS:** `services.ddns-updater` (qdm12), kein Cloudflared-Tunnel — Fritzbox Port-Forward 80/443 + Caddy ACME.
3. **DNS-Guard:** optionaler Timer in `modules/10-gateway.nix`, liest dasselbe Token-File.
4. **Später (Stufe 9+):** SOPS ersetzt `profile.local`-Klartext; Provision-Script wird dünn oder entfällt.

## Konsequenzen

### Positiv

- Dynamische IP (Speedport) → Cloudflare A-Record ohne manuelles Dashboard.
- Kein Tunnel — direkter Caddy-Ingress bleibt Architektur-Kern.
- Migrationspfad dokumentiert; mynixos-Muster ohne `options.my.meta.*`.

### Negativ

- Token liegt bis SOPS in gitignored `profile.local.nix` — nicht auf anderen Hosts kopieren.
- HTTP-01 ACME braucht erreichbare Ports 80/443 am Router.

### Was bewusst fehlt

- **Cloudflared Tunnel** — ersetzt Caddy-Ingress, widerspricht q958-Design.
- **ClamAV** — offen; separates ADR wenn AV auf Gateway-Ebene gewünscht.

### Implementierung

| Artefakt | Pfad |
|----------|------|
| Gateway | `modules/10-gateway.nix` |
| Provision | `machines/q958/secrets.nix` |
| Registry | `NIXH-10-GTW-001` |