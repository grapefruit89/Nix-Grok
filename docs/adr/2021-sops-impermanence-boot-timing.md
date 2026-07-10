---
meta:
  role: doc
  purpose: SOPS Boot-Timing mit Impermanence — withdrawn zugunsten ADR-2024
  status: withdrawn
  date: 2026-06-30
  tags:
    - sops
    - impermanence
    - withdrawn
---
# ADR-2021: SOPS Boot-Timing mit Impermanence — WITHDRAWN {#adr-2021-sops-boot-timing-mit-impermanence-withdrawn}

> **WITHDRAWN** — Entfällt mit [ADR-2024: systemd-creds + TPM2](2024-systemd-creds-tpm.md) (2026-07-05).
>
> sops-nix wird nicht eingesetzt. Die hier beschriebene Race-Condition existiert
> damit nicht — das Modul `05-sops.nix` wurde durch `05-creds.nix` ersetzt.

---

**Status:** ~~Accepted (Vorarbeit für Stufe 9)~~ **Withdrawn**
**Datum:** 2026-06-30
**Withdrawn:** 2026-07-05 (ADR-2024)

---

## Historischer Kontext {#historischer-kontext}

Dieses ADR beschrieb eine Boot-Timing-Race zwischen `sops-install-secrets.service`
und Impermanence-Bind-Mounts (`local-fs.target`). Die Lösung war implementiert in
`05-sops.nix` (Commit 2026-06-30).

Da sops-nix durch systemd-creds ersetzt wurde (ADR-2024), ist dieses Problem
gegenstandslos. `05-sops.nix` existiert nicht mehr im Repo.

## Siehe auch {#siehe-auch}

- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md)
- [ADR-2006 — SOPS-Migration (superseded)](2006-sops-migration-path.md)
