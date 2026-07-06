---
meta:
  role: doc
  purpose: ADR-5030 — Media-Stack Architektur-Inventory (was bereits implementiert war)
  status: accepted
  date: 2026-07-05
  betrifft:
    - modules/50-media/51-jellyfin.nix
    - modules/50-media/arr-helper.nix
    - lib/caddy-ingress.nix
    - lib/service-factory.nix
  docs:
    - docs/adr/2008-nftables-l4-hardening.md
    - docs/adr/2024-systemd-creds-tpm.md
    - docs/adr/028-systemd-service-isolation.md
  tags:
    - media
    - security
    - caddy
    - jellyfin
    - navidrome
    - inventory
---

# ADR-5030: Media-Stack Architektur-Inventory

## Kontext

Abgleich eines externen Specs (nixflix/nixarr-Analyse) gegen den tatsächlichen Codestand.
Dokumentiert was bereits implementiert war und warum bestimmte Vorschläge NICHT umgesetzt wurden.

## Entscheidungen

### 1. Navidrome Subsonic-Bypass — bereits implementiert

`lib/caddy-ingress.nix` → `genNavidromeVhost` (Zeile ~82):

```caddy
@navidrome_api {
  path /rest/*
  path /share/*
}
handle @navidrome_api {
  # kein SSO — Subsonic-Clients (Symfonium, DSub) nutzen Token-Auth in URL/Header
  reverse_proxy ...
}
handle {
  import sso_auth
  reverse_proxy ...
}
```

`/rest/*` = OpenSubsonic-API-Protokoll. Subsonic-Clients können keinen Browser-OAuth-Flow
durchlaufen. `/share/*` = Navidrome Share-Links — ebenfalls ohne Login erreichbar by design.

### 2. Servarr /api/* LAN-only — durch nftables abgedeckt

Der Spec schlug einen Caddy-Filter für Servarr `/api/*` vor. Unnötig, weil:

- `nftables-rules.nix`: `skuidArrGuard` sperrt Servarr-UIDs auf LAN/Tailscale-Quellen (L4)
- `in_lan`-Chain: akzeptiert alles vom LAN — WAN-Traffic erreicht diese Ports nicht
- Caddy würde denselben Traffic nochmals filtern (doppelt gemoppelt)

**Kein Caddy-Layer ergänzt.** Wenn später ein einzelner Endpunkt granularer
abgesichert werden soll: `(private_admin)` Snippet aus `caddy-snippets.nix` nutzen.

### 3. freeformType + _secret AST-Injection — gestrichen

Vorgeschlagenes Pattern: Nix-Submodule mit `{ _secret = "/path"; }` Platzhalter →
sanitizeSecrets-Funktion für Store-sicheres JSON → jq-Injection zur Laufzeit.

**Nicht implementiert**, weil systemd-creds (ADR-2024) das Secret-Problem auf
Systemebene eleganter löst:

- Dev (Stufe < 9): `/var/lib/secrets/*` via `secrets-provision` (EnvironmentFile)
- Production (Stufe 9+): `LoadCredentialEncrypted=` → `$CREDENTIALS_DIRECTORY/<name>`
- TPM-Versiegelung: ein Flip auf `my.creds.useTpm = true` in rollout.nix

Bash-Skripte + `EnvironmentFile` reicht für API-Payloads aus. freeformType bringt
Typ-Sicherheit auf Kosten massiver Komplexität bei minimalem Gewinn.

### 4. Was bereits fertig war (gegen Spec-Erwartung)

| Feature | Datei | Zeile |
|---------|-------|-------|
| tmpfs-Transcoding (6G, nosuid, nodev) | 51-jellyfin.nix | ~131 |
| RAM-adaptiver Cleanup-Timer (3 Schwellen) | 51-jellyfin.nix | ~194 |
| Jellyfin Config-Seeding (pkgs.runCommand) | 51-jellyfin.nix | ~103 |
| SSO-Plugin v4.0.0.3 als Nix-Derivation | 51-jellyfin.nix | ~65 |
| IPAddressAllow/Deny für Jellyfin | 51-jellyfin.nix | ~303 |
| UMask=0002 für alle *arr-Dienste | arr-helper.nix | ~97 |
| Navidrome Subsonic-Bypass /rest/* /share/* | caddy-ingress.nix | ~87 |
| skuidArrGuard (L4-Firewall) | nftables-rules.nix | – |
| Memory-Policy OOMScoreAdjust, MemoryMax | lib/memory-policy.nix | – |
| locale SSoT (LANG aus systemd) | 53-sabnzbd.nix | – |

## Konsequenzen

- Kein neuer Code für Navidrome, Servarr-API-Filter, freeformType
- Offene Tasks: Recyclarr (ADR folgt), Exportarr, Plugin-Factory, IPAddressAllow in factory
- Zukünftige Analysen: zuerst Codestand prüfen, dann Spec übernehmen
