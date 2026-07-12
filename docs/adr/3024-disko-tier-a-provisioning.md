---
meta:
  role: doc
  purpose: ADR-3024 — disko Tier-A q958 — CLI-Modi, ESP-Sizing, Legacy-Prune
  status: accepted
  date: 2026-07-12
  betrifft:
    - machines/q958/disko.nix
    - machines/q958/disko-enabled.nix
    - scripts/disko-q958.sh
    - machines/q958/disko-deprecations.json
  docs:
    - docs/guides/GUIDE-storage-tiers.md
    - https://github.com/nix-community/disko/blob/master/docs/reference.md
  tags:
    - adr
    - storage
    - disko
    - tier-a
    - dr
---

# ADR-3024: disko Tier-A Provisioning (q958) {#adr-3024}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-12 |
| **Host** | q958 |

---

## Kontext {#kontext}

q958 hat eine Einzelplatte (Tier A, `/dev/sda`) mit GPT, vfat ESP und ext4 Root.
Partitionierung soll deklarativ in `machines/q958/disko.nix` liegen; das laufende
System (Stufe 0–8) mountet weiter per Label in `hardware.nix`.

nix-community/disko hat die CLI-Modi präzisiert: `--mode disko` ist ein Alias für
`destroy,format,mount` und gilt als veraltet. KI-Agenten greifen oft auf alte
Beispiele im Web zurück — ohne explizite Guardrails wird der Legacy-Befehl erneut genutzt.

---

## Entscheidung {#entscheidung}

### 1. Explizite disko-CLI-Modi (Pflicht) {#cli-modi}

**Einziger Einstieg für Agenten und Menschen:** `scripts/disko-q958.sh`

| Subbefehl | Internes `--mode` | Wirkung |
|-----------|-------------------|---------|
| `plan` | `destroy,format,mount` + `--dry-run` / `script` | Nur anzeigen, nichts schreiben |
| `install` | `destroy,format,mount` | Volle Neuinstallation (destruktiv) |
| `destroy` | `destroy` | Partitionstabellen löschen |
| `format` | `format` | GPT + FS anlegen |
| `format-mount` | `format,mount` | Formatieren und mounten |
| `mount` | `mount` | Bestehendes Layout mounten |

**Verboten:** Subbefehl `disko` und direktes `nix run … disko -- --mode disko` —
`disko-q958.sh disko` bricht mit exit 2 ab.

Flake-Referenz für disko CLI: `/etc/nixos#q958` (intern: `diskoConfigurations.q958`).

**KRITISCH:** `disko script` **führt aus** — auf laufendem q958 verboten. `plan` = `--dry-run` + Store-`cat`.

Referenz: [disko reference.md](https://github.com/nix-community/disko/blob/master/docs/reference.md)

### 1b. Live-System-Schutz {#live-guard}

`disko-q958.sh install|destroy|format*` bricht ab, wenn Tier-A = aktuelles Root-Device.
Lernen auf Developer-PC: `plan` oder `vm` (QEMU `q958-disko-vm`).

### 1c. diskoManaged-Switch {#switch}

| `diskoManaged` | Aktiv | Inaktiv |
|----------------|-------|---------|
| `false` (jetzt) | hardware.nix mounts, relabelTierALabels | disko-Modul im switch |
| `true` (Reinstall) | disko-enabled.nix → fileSystems | Legacy-Marker → prune |

Scope: `machines/q958/disko-switch.nix` + `disko-deprecations.json` → `scope`.

### 2. ESP 512M + generationLimit {#esp-sizing}

**SSoT:** `profile.nix` → `storage.tierA.boot.espSize = "512M"` (disko.nix liest das).

systemd-boot kopiert **pro Kernel-Version** ein Paar (~47 MB: bzImage.efi + initrd.efi).
Viele NixOS-Generationen mit **gleichem** Kernel → viele `.conf` (~4 KB), **ein** Paar.
Details: [GUIDE-boot-esp.md](../guides/GUIDE-boot-esp.md).

| Szenario | ESP | generationLimit | Begründung |
|----------|-----|-----------------|------------|
| Dev (Rollback) | 512M | 15 | Menü-Einträge, nicht ESP-Größe |
| Production | 512M | 5–7 | Aufgeräumtes Menü |
| Worst-Case ESP | 512M | — | ≤2 Kernel-Paare ≈ 200 MB << 512M |

**Nur ext4** auf Tier A — kein btrfs (Projektregel).

### 3. Phase 3 — Legacy-Code nach disko-Reinstall {#phase-3-prune}

Drei Schichten bis Legacy-Mounts und `relabelTierALabels` entfallen:

1. **Flag:** `storage.tierA.diskoManaged = true` in `profile.nix`
2. **Runtime:** `disko-enabled.nix` importiert disko-Modul + `diskoConfigurations.q958`
3. **Prune:** KI-Workflow mit Verify-Gate:
   - `scripts/disko-verify-active.sh` (exit 0)
   - `scripts/disko-prune-deprecated.sh check`
   - `scripts/disko-prune-deprecated.sh apply`
   - erneut `nixos-rebuild-safe dry`

Manifest: `machines/q958/disko-deprecations.json`  
Marker: `# DEPRECATED-DISKO-START: <id>` … `# DEPRECATED-DISKO-END: <id>`

**Niemals ohne verify löschen:** `disko.nix`, `disko-enabled.nix`, disko-Skripte, Manifest.

Verify prüft u. a. GPT-Partlabels `disk-tierA-NIXBOOT` / `disk-tierA-NIXPERSIST`
(disko-Schema) statt Legacy `BOOT` / `NIXHOME_PERSIST`.

---

## Konsequenzen {#konsequenzen}

- Shell-Aliases in `09-nix-tools.nix`: `disko-plan`, `disko-install`, `disko-mount`
- Subbefehl `disko` → exit 2 (KI muss `install` lesen)
- Laufendes q958: `diskoManaged = false` — kein disko-Modul im `switch`
- DR: `disko-q958.sh install` → `nixos-install` → `diskoManaged = true` → verify → prune

---

## Siehe auch {#siehe-auch}

- [GUIDE-disko-learning.md](../guides/GUIDE-disko-learning.md) — Doku-Index, Ökosystem, Lernpfad, Install-Weg
- [GUIDE-storage-tiers.md](../guides/GUIDE-storage-tiers.md#disko-tier-a)
- [ADR-020](020-no-legacy-explicit-stack.md) — systemd-boot, generationLimit
- [ADR-012](012-modern-cli-tools.md) — Shell-Aliases für Agenten