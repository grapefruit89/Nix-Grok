---
meta:
  role: doc
  purpose: Notfall nach disko-Unfall — Generationen, Recovery, Live-USB
  date: 2026-07-12
  status: emergency
  tags:
    - emergency
    - disko
    - recovery
---

# Emergency Recovery (disko-Unfall 2026-07-12) {#emergency}

## Wichtigste Antwort: Sind alle Generationen weg? {#generationen}

**Nein — höchstwahrscheinlich nicht.**

| Was | Zustand | Generationen |
|-----|---------|--------------|
| **sda2 (ext4 /nix/store)** | Primärer Superblock beschädigt, **kein mkfs** auf sda2 | **Alle** Store-Pfade noch auf Platte (Solange nicht neu formatiert) |
| **sda1 (ESP /boot)** | Partition neu, **kein vfat** | Boot-Einträge weg — **Store unberührt** |
| **Jetzt (ohne Reboot)** | Root aus Kernel-Cache | `/nix/store` lesbar, Gen **169+** aktiv |

**Nur die aktuelle Generation?** Nein. disko hat **nicht** `mkfs.ext4` auf sda2 abgeschlossen.
Alle Generationen liegen als Dateien im selben ext4 — ein kaputter Superblock betrifft **das
gesamte FS**, aber die **Datenblöcke** sind sehr wahrscheinlich noch da.

**Nach Reboot ohne Fix:** System startet nicht — Daten aber oft per `e2fsck` rettbar.

**Komplett verloren** wird sda2 nur bei: `disko-q958.sh install` / `mkfs.ext4` (Neuinstall-Pfad).

---

## Nicht neu booten {#kein-reboot}

Solange das System läuft: **kein reboot**. Kernel hält sda2 gemountet.

Optional jetzt (ohne Reboot):

```bash
# Config sichern (kein profile.local — gitignored!)
sudo tar -czf /tmp/nixos-etc-backup-$(date +%Y%m%d).tar.gz -C /etc nixos \
  --exclude=nixos/profile.local.nix --exclude=nixos/.git

# Store-Größe prüfen
du -sh /nix/store
```

`profile.local.nix` separat auf USB sichern!

---

## Live-USB: Ein Befehl {#one-liner}

Nach `git push` der Branch `emergency/disko-accident-2026-07-12`:

```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh | sudo bash
```

Oder mit Repo auf zweitem USB:

```bash
sudo bash /mnt/usb/Nix-Grok/scripts/emergency-bootstrap-q958.sh recover
```

### recover (empfohlen — exakt jetziges System)

1. `e2fsck` mit Backup-Superblock auf `/dev/sda2`
2. Mount `/dev/sda2` → `/mnt`, ESP neu vfat → `/mnt/boot`
3. `nixos-enter` + `switch-to-configuration boot` von **letztem system-Profil**

→ **Gleiche Generationen**, gleicher Store, kein Neu-Download der Welt.

### install (nur wenn recover scheitert)

1. `disko-q958.sh install` — **löscht alles** auf sda
2. `nixos-install --flake /etc/nixos#q958`
3. Frisches System aus Git — Store leer, neue Generation 1

---

## Brauche ich eine Custom-ISO? {#iso}

**Nein.** Standard [NixOS Minimal ISO](https://nixos.org/download.html) + curl/clone reicht.
Custom ISO nur für Airgap (später).

---

## Verhindern (ab Emergency-Branch) {#guard}

- `machines/q958/.live-system-no-destructive-disko` — Marker
- `disko-q958.sh` blockiert **jeden** direkten disko-Aufruf auf Live-Root (außer `--dry-run`)
- `profile.d/disko-live-guard.sh` — blockiert `nix run … disko … script`
- **Niemals:** `nix run github:nix-community/disko -- script …`