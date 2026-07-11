---
meta:
  role: doc
  purpose: ADR-2006 SOPS-Migration — SUPERSEDED by ADR-2024
  status: superseded
  date: 2026-06-17
  superseded_by: docs/adr/2024-systemd-creds-tpm.md
  betrifft:
    - machines/q958/secrets.nix
    - machines/q958/profile.local.nix
    - modules/10-network/1090-host-network.nix
  docs:
    - docs/adr/README.md
    - docs/adr/2024-systemd-creds-tpm.md
  tags:
    - adr
    - sops
    - secrets
    - superseded
---

# ADR-2006: SOPS-Migration ~~— SUPERSEDED~~ {#adr-2006}

> **SUPERSEDED** — Ersetzt durch [ADR-2024: systemd-creds + TPM2](2024-systemd-creds-tpm.md) (2026-07-05).
>
> Der geplante sops-nix-Migrationspfad wurde nach Analyse verworfen.
> sops-nix ist für q958 (single-host, rotierbare Keys) ein Anti-Pattern.
> Siehe [ANTIPATTERNS.md#sops-nix](../guides/ANTIPATTERNS.md#sops-nix).

---

| Feld | Wert |
|------|------|
| **Status** | ~~accepted~~ **superseded** |
| **Datum** | 2026-06-17 |
| **Superseded by** | [ADR-2024](2024-systemd-creds-tpm.md) |

## Historischer Kontext (zur Nachvollziehbarkeit) {#historischer-kontext-zur-nachvollziehbarkeit}

Der ursprüngliche Plan sah vor:

- **Stufe < 9**: `secrets-provision` + `profile.local.nix` → `/var/lib/secrets/`
- **Stufe 9+**: sops-nix ersetzt Klartext-Provision

Dieser Plan wurde am 2026-07-05 verworfen, weil:

1. sops-nix bringt für single-host keinen Mehrwert (kein Multi-Host-Sharing, kein Git-Versionierungsbedarf)
2. Age-Key auf Disk ist eine reale Schwachstelle (systemd-creds + TPM hat dieses Problem nicht)
3. Flake-Input + `.sops.yaml` + Boot-Timing-Komplexität (ADR-2021) für null echten Sicherheitsgewinn

## Aktueller Stand {#aktueller-stand}

```text
Dev (Stufe < 9):  profile.local.nix → secrets-provision → /var/lib/secrets/*
                  (unverändert)

Production (Stufe 9+): systemd-creds → /var/lib/credstore.encrypted/*.cred
                       → LoadCredentialEncrypted= in Service-Units
                       → ADR-2024
```

## Siehe auch {#siehe-auch}

- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — aktuelle Strategie
