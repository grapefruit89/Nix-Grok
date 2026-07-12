---
meta:
  role: doc
  purpose: Notfall nach disko-Unfall — Was passiert ist, Recovery, Guards, Ein-Befehl
  date: 2026-07-12
  status: current
  tags:
    - emergency
    - disko
    - recovery
    - dr
  docs:
    - README.md
    - scripts/emergency-bootstrap-q958.sh
    - docs/guides/GUIDE-disko-learning.md
---

# Emergency Recovery — disko-Unfall q958 (2026-07-12)

> **Wenn du nur eine Sache merken willst:** Nach einem disko-Unfall auf **laufendem**
> q958 **nicht rebooten**, vom **NixOS Live-USB** mit `recover` starten — nicht `install`.
> Der `/nix/store` mit allen Generationen ist sehr wahrscheinlich noch auf der Platte.

---

## Was ist passiert? (Wann, Wo, Wieso)

| | |
|---|---|
| **Wann** | 2026-07-12 |
| **Wo** | q958, Systemplatte `/dev/sda` (Tier-A SSD) |
| **Auslöser** | `nix run github:nix-community/disko -- script …` auf dem **laufenden** System ausgeführt — nicht nur angezeigt, sondern **ausgeführt** |
| **Wieso so schlimm** | `disko script` im Modus `destroy,format,mount` partitioniert und formatiert **sofort** — es gibt kein Dry-Run |

**Ursache:** Der Befehl `nix run … disko -- script` generiert ein Shell-Skript und **führt es direkt aus**.
`disko plan` / `--dry-run` wäre sicher gewesen.

**Branch mit Guards + Skripte:** `emergency/disko-accident-2026-07-12` (GitHub).
**Dokumentation auf `main`/`master`:** diese Datei — damit das Wissen nicht verloren geht.

---

## Was wurde beschädigt — und was NICHT

| Partition | Was passiert ist | Generationen / Daten |
|-----------|------------------|----------------------|
| **sda1 (ESP /boot)** | Neue 512M-GPT-Partition `disk-tierA-NIXBOOT`, **kein vfat** | Boot-Einträge weg — **Store unberührt** |
| **sda2 (ext4 /)** | Primärer Superblock beschädigt, **kein `mkfs.ext4`** | **Alle** Generationen liegen noch als Dateien in `/nix/store` |

**Nur die aktuelle Generation?** **Nein.**

disko hat auf sda2 **nicht** neu formatiert — nur wenige Bytes am Superblock zerstört.
Solange du **nicht** `disko-q958.sh install` oder `mkfs.ext4` ausführst, sind alle
Store-Pfade (Gen 85 … 336+) sehr wahrscheinlich noch auf der Platte.

| Zustand | Bedeutung |
|---------|-----------|
| **Jetzt (ohne Reboot)** | `/nix/store` lesbar — Kernel hält sda2 aus dem Mount-Cache |
| **Reboot ohne Fix** | Startet nicht — Daten oft per `e2fsck` mit Backup-Superblock rettbar |
| **Komplett verloren** | Nur bei `install` / `mkfs.ext4` — bewusste Neuinstallation |

---

## Sofort-Maßnahmen (laufendes System, vor Reboot)

```bash
# 1. NICHT rebooten

# 2. Config sichern (profile.local.nix ist gitignored — separat!)
sudo tar -czf /tmp/nixos-etc-backup-$(date +%Y%m%d).tar.gz -C /etc nixos \
  --exclude=nixos/profile.local.nix --exclude=nixos/.git

# 3. profile.local.nix auf USB sichern
sudo cp /etc/nixos/machines/q958/profile.local.nix /media/<USB>/

# 4. Store prüfen
du -sh /nix/store
ls /nix/var/nix/profiles/ | grep '^system-' | wc -l
```

---

## Recovery: Ein Befehl vom Live-USB

**Voraussetzung:** [NixOS Minimal ISO](https://nixos.org/download.html) auf USB, q958 davon booten.

**Schritt-für-Schritt inkl. SSH vom Hauptrechner:** [`docs/guides/GUIDE-recovery-live-ssh.md`](guides/GUIDE-recovery-live-ssh.md)

**Ohne langen curl (zweiter USB, vor dem Reboot vorbereiten):** `sudo bash /etc/nixos/scripts/prepare-recovery-usb.sh` → am Live-USB: `bash /mnt/recover`


```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh | sudo bash
```

Interaktiv: **`recover`** wählen (empfohlen). Oder direkt:

```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh | sudo bash -s recover
```

**Mit Repo auf zweitem USB** (offline):

```bash
sudo bash /mnt/usb/Nix-Grok/scripts/emergency-bootstrap-q958.sh recover
```

### `recover` — gleiches System, gleiche Generationen (empfohlen)

1. `e2fsck` mit Backup-Superblock auf `/dev/sda2`
2. `/dev/sda2` → `/mnt`, ESP neu als vfat `NIXBOOT` → `/mnt/boot`
3. `nixos-enter` + `switch-to-configuration boot` vom **letzten `system`-Profil**

→ Gleicher Store, gleiche Generationen, kein Neu-Download.

### `install` — nur wenn `recover` scheitert (DATEN WEG)

1. `disko-q958.sh install` — **löscht alles** auf sda
2. `nixos-install --flake /etc/nixos#q958 --impure`
3. Frisches System — Store leer, Generation 1

**Vor `install`:** `profile.local.nix` muss unter `/mnt/etc/nixos/machines/q958/` liegen.

---

## Guards — damit das nie wieder passiert

Implementiert auf Branch `emergency/disko-accident-2026-07-12` (nach Recovery auf `main` mergen):

| # | Guard | Wirkung |
|---|-------|---------|
| 1 | `machines/q958/.live-system-no-destructive-disko` | Marker: Live-System auf Tier-A |
| 2 | **`scripts/nix` + `nix.package`** | **Systemweiter nix-Wrapper** — blockiert `script`/`destroy` auch unter `sudo` und bei `/run/current-system/sw/bin/nix` |
| 3 | `scripts/lib/nix-disko-guard.sh` | Gemeinsame Block-Logik (Quelle der Wahrheit) |
| 4 | `scripts/disko-q958.sh` | Auf Live-Root nur `plan` und `vm` — alles andere **exit 99** |
| 5 | `profile.d/50-nix-live-guard-path.sh` | `/etc/nixos/scripts` vorne im PATH |
| 6 | `security.sudo.extraConfig` | `secure_path` enthält Wrapper — `sudo nix` geschützt |
| 7 | `docs/EMERGENCY-RECOVERY.md` | Diese Datei |

**Nach `nixos-rebuild switch`:** Selbst `sudo /run/current-system/sw/bin/nix run … disko -- script` wird mit **exit 99** abgebrochen.

### Verboten auf q958 (laufendes System)

```bash
# NIEMALS — führt destroy/format aus:
nix run github:nix-community/disko -- script …
nix run github:nix-community/disko -- --mode destroy,format,mount …

# Sicher — nur anzeigen:
/etc/nixos/scripts/disko-q958.sh plan    # oder: disko-plan (Alias)
/etc/nixos/scripts/disko-q958.sh vm      # Lern-VM
```

**Merksatz:** `disko script` = ausführen. `disko plan` / `--dry-run` = anzeigen.

---

## Brauche ich eine Custom-ISO?

**Nein.** Standard NixOS Minimal ISO + curl/clone reicht.
Custom Offline-ISO nur für Airgap (später, optional).

---

## Nach erfolgreicher Recovery

1. Booten → solltest dieselbe Generation / denselben Store haben
2. `sudo nixos-rebuild-safe.sh dry` (Mensch)
3. Guards von Emergency-Branch mergen
4. Optional: `diskoManaged = false` lassen bis zur bewussten Stufe-3-Neuinstallation
5. `profile.local.nix` prüfen — war separat gesichert?

Weitere disko-Doku: `docs/guides/GUIDE-disko-learning.md` (Emergency-Branch).

---

## Git-Branches (Übersicht)

| Branch | Inhalt |
|--------|--------|
| `master` / `main` | Normaler Entwicklungsstand — **diese Recovery-Doku** |
| `emergency/disko-accident-2026-07-12` | Bootstrap-Skript, disko-Infrastruktur, Guards |

Recovery-Skript liegt bewusst auf dem Emergency-Branch (getestet, curl-fähig).
Die **Anleitung** liegt auf `main`, damit sie nicht verloren geht.

---

## Siehe auch

- [README.md](../README.md) — Notfall-Box oben
- [AGENTS.md](../AGENTS.md) — Harte Regel #9 (disko)
- [scripts/emergency-bootstrap-q958.sh](../scripts/emergency-bootstrap-q958.sh) (Emergency-Branch)
