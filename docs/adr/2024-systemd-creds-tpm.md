---
meta:
  role: doc
  purpose: ADR-2024 systemd-creds + TPM2 als Secrets-Strategie — ersetzt sops-nix
  status: accepted
  date: 2026-07-05
  betrifft:
    - modules/00-core/05-creds.nix
    - machines/q958/rollout.nix
    - flake.nix
  docs:
    - docs/adr/2006-sops-migration-path.md
    - docs/guides/ANTIPATTERNS.md
    - docs/guides/GUIDE-security-secrets.md
  tags:
    - adr
    - secrets
    - systemd-creds
    - tpm2
---

# ADR-2024: systemd-creds + TPM2 statt sops-nix {#adr-2024}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-05 |
| **Ersetzt** | ADR-2006, ADR-2021 |
| **Host** | q958 |

## Kontext {#kontext}

Die ursprüngliche Planung (ADR-2006) sah sops-nix ab Stufe 9 vor. Nach Analyse des
konkreten Nutzerprofils (single-host, alle API-Keys beim Anbieter rotierbar, kein
Multi-Host-Repo-Sharing) stellt sich sops-nix als Anti-Pattern heraus:

- **Komplexität ohne Nutzen**: Der Hauptvorteil von sops-nix (verschlüsselte Secrets
  versionierbar im Git, teilbar über mehrere Hosts) ist für q958 wertlos.
- **Age-Key auf Disk**: Der Decryption-Key liegt in `/etc/sops/age/keys.txt` — wer ihn
  hat, hat alles. Bei systemd-creds verlässt der Sealing-Key beim TPM-Betrieb den Chip nie.
- **Nix-Store-Leak-Risiko**: sops-Dateipfade und Strukturen fließen durch die
  Nix-Evaluierung und können im Store landen.
- **Flake-Input-Overhead**: sops-nix als Flake-Input + `.sops.yaml` + creation rules für
  null echter Mehrwert.
- **Race-Condition bei Impermanence**: ADR-2021 dokumentiert die Boot-Timing-Komplexität,
  die durch sops entsteht — entfällt komplett bei systemd-creds.

TPM ist auf q958 vollständig verfügbar (`systemd-analyze has-tpm2` → yes, alle Schichten).

## Entscheidung {#entscheidung}

**sops-nix wird ersetzt durch systemd-creds.**

Zweistufige Migration:

### Stufe A — Ohne TPM (aktuell, Dev-Betrieb) {#stufe-a-ohne-tpm-aktuell-dev-betrieb}

```bash
# Credential versiegeln (host key, /var/lib/systemd/credential.secret) {#credential-versiegeln-host-key-varlibsystemdcredentialsecret}
printf '%s' 'WERT' | systemd-creds encrypt --name=sonarr_api_key \
  - /var/lib/credstore.encrypted/sonarr_api_key.cred
```text

Entschlüsselung erfolgt automatisch durch systemd via `LoadCredentialEncrypted=` in der
Unit. Das Secret landet nur in `$CREDENTIALS_DIRECTORY/<name>`, nur für diesen Service
sichtbar, automatisch bereinigt beim Stop.

### Stufe B — Mit TPM (zukünftig, ein Boolean-Flip) {#stufe-b-mit-tpm-zukuenftig-ein-boolean-flip}

```nix
# In rollout.nix oder profile.nix: {#in-rolloutnix-oder-profilenix}
my.creds.useTpm = true;  # war: false
```

Dann Credentials neu versiegeln (einmalig):
```bash
printf '%s' 'WERT' | systemd-creds encrypt --with-key=tpm2 --name=sonarr_api_key \
  - /var/lib/credstore.encrypted/sonarr_api_key.cred
```nix

Kein weiterer Rebuild nötig — nur Credentials neu erstellen.

### NixOS-Integration {#nixos-integration}

```nix
# Service-Unit erhält Credential transparent: {#service-unit-erhaelt-credential-transparent}
systemd.services.sonarr.serviceConfig = {
  LoadCredentialEncrypted = "sonarr_api_key:${config.my.creds.storeDir}/sonarr_api_key.cred";
};
# Im Service: $CREDENTIALS_DIRECTORY/sonarr_api_key {#im-service-credentials_directorysonarr_api_key}
```

### Deklarative Credentials-Liste {#deklarative-credentials-liste}

```nix
my.creds = {
  enable = true;  # erstAb 9
  useTpm = false; # → true für TPM-Migration
  keys = [ "sonarr_api_key" "radarr_api_key" "cloudflare_api_token" ];
};
```text

Fehlendes `.cred`-File → Warnung bei `nixos-rebuild switch` mit Siegel-Befehl.

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- **Kein Flake-Input**: `sops-nix` aus `flake.nix` entfernt.
- **Kein Age-Key auf Disk**: Bei TPM-Betrieb verlässt Sealing-Key den Chip nie.
- **Kein `.sops.yaml`**: Keine creation rules, keine Schlüssel-Verwaltung.
- **Kein Nix-Store-Leak**: Credentials sind Laufzeit-Artefakte, kein Nix-Input.
- **TPM-Migration = 1 Boolean**: `useTpm = false → true`, Credentials neu versiegeln.
- **Automatisches Cleanup**: systemd bereinigt `$CREDENTIALS_DIRECTORY` nach Service-Stop.
- **Schmalere Blast-Radius**: Decryption nur für die spezifische Unit, nicht systemweit.

### Negativ / Trade-offs {#negativ}

- **Host-Bindung**: Credentials mit host key oder TPM sind nicht auf anderen Rechnern
  entschlüsselbar. Bei Mainboard-Defekt: Keys beim Anbieter neu generieren (~30 Min).
  → Kein Problem bei q958 (alle Keys rotierbar).
- **Nicht im Git-Repo**: credstore liegt außerhalb. Struktur bleibt deklarativ (welche
  Unit welchen Credential lädt), Werte sind imperativ-lokal.
  → Für API-Keys (Laufzeit-Zustand) korrekt, kein Config-Zustand.
- **Stufe < 9**: Bis Stufe 9 bleibt `secrets-provision` + `profile.local.nix` aktiv.
  Der Wechsel passiert sauber beim Production-Cutover.

## Migrationspfad {#migrationspfad}

```
Dev (Stufe < 9):  profile.local.nix → secrets-provision → /var/lib/secrets/*
                  (unverändert, bewährt)

Production (Stufe 9):
  my.creds.enable = true; useTpm = false;
  → systemd-creds encrypt (host key) → /var/lib/credstore.encrypted/*.cred
  → LoadCredentialEncrypted= in Service-Units

TPM (optional, später):
  my.creds.useTpm = true;
  → Credentials neu versiegeln mit --with-key=tpm2
  → kein Rebuild nötig
```bash

## Alternativen verworfen {#alternativen}

- **sops-nix beibehalten** — Age-Key auf Disk, Flake-Input, kein echter Mehrwert
  für single-host-Profil. Abgelehnt als Anti-Pattern (ANTIPATTERNS.md#sops-nix).
- **agenix** — Gleiche strukturelle Schwäche wie sops-nix (SSH-Key als Decryption-Key
  auf Disk). Abgelehnt.
- **Vaultwarden als Secret-Backend** — Externes System, API-Abhängigkeit beim Boot.
  Für manuelles Key-Management geeignet, nicht als systemd-Unit-Secret-Quelle. Abgelehnt.

## Siehe auch {#siehe-auch}

- [ADR-1034 — secrets-portal Architektur](1034-secrets-portal-architecture.md)
- [ADR-2006 — SOPS-Migration](2006-sops-migration-path.md) — Superseded by this ADR
- [ADR-2021 — SOPS Boot-Timing](2021-sops-impermanence-boot-timing.md) — Withdrawn (entfällt)
- [ANTIPATTERNS.md#sops-nix](../guides/ANTIPATTERNS.md#sops-nix) — sops-nix als Anti-Pattern
- [GUIDE-security-secrets.md](../guides/GUIDE-security-secrets.md) — Betriebsguide aktualisiert
- `modules/00-core/05-creds.nix` — NixOS-Modul
