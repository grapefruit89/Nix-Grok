---
meta:
  role: doc
  purpose: Zero-Touch Recovery q958 — deklarativ, minimal manuelle Schritte
  date: 2026-07-12
  status: current
  tags:
    - recovery
    - zero-touch
    - dr
  docs:
    - docs/EMERGENCY-RECOVERY.md
    - docs/guides/GUIDE-recovery-live-ssh.md
---

# Zero-Touch Recovery q958

> **Ziel:** Boot vom USB → `recover` läuft automatisch → Reboot → fertig.
> Kein Tippen, kein curl, kein `install`, kein interaktives Menü.

---

## Was du manuell machst (unvermeidbar)

| Schritt | Warum nicht automatisierbar |
|---------|----------------------------|
| **1× Kit vorbereiten** (jetzt, System läuft noch) | USB beschreiben, ISO bauen |
| **1× Reboot** | Hardware muss vom USB starten |
| **1× Boot-Menü: USB wählen** | Firmware-Entscheidung (F12/F8/DEL) |
| **Warten** (~5–20 Min) | e2fsck + Bootloader |
| **USB raus** (vor oder nach Auto-Reboot) | Sonst bootet wieder USB |

**Alles andere** ist deklarativ im Manifest und in der Custom-ISO.

---

## Architektur

```
recovery-constants.nix     ← öffentliche Werte (Disk, Netz, Labels)
        ↓
manifest.env             ← Shell-Variablen (recover, by-id, auto-reboot)
        ↓
Custom ISO (Q958RECOVER) ← bootet → systemd q958-auto-recover.service
        ↓
emergency-bootstrap.sh recover
  1. by-id verifizieren (falsche Platte = Abbruch)
  2. e2fsck Backup-Superblock
  3. ESP vfat NIXBOOT
  4. switch-to-configuration boot
  5. Auto-Reboot (45s)
```

**Sicherheitsgarantien (kein install):**

- `RECOVERY_MODE=recover` hardcoded im Auto-Pfad
- `install` blockiert ohne `INSTALL_CONFIRM=destroy`
- Abbruch wenn von kaputtem `sda` gebootet (nicht Live-USB)
- `RECOVERY_DISK_BY_ID` muss zu `sda` passen

---

## Vorbereitung — ein Befehl (empfohlen)

### 1. Kit-Datei anlegen

```bash
sudo cp /etc/nixos/machines/q958/recovery-kit.env.example \
        /etc/nixos/machines/q958/recovery-kit.env
```

`recovery-kit.env` anpassen — **Gerätenamen prüfen**:

```bash
lsblk -o NAME,SIZE,TYPE,LABEL,MODEL
# RECOVERY_ISO_DEV=/dev/sdb   ← USB für Recovery-ISO (NICHT sda!)
```

### 2. Kit bauen und USB flashen

```bash
cd /etc/nixos
sudo RECOVERY_YES=1 RECOVERY_BUILD_ISO=1 RECOVERY_FLASH_ISO=1 \
  RECOVERY_ISO_DEV=/dev/sdb \
  bash scripts/prepare-recovery-kit.sh
```

Dauer: ISO-Build ~10–30 Min (einmalig).

### 3. Optional: zweiter Stick (profile.local.nix)

```bash
sudo RECOVERY_YES=1 RECOVERY_DATA_DEV=/dev/sdc \
  bash scripts/prepare-recovery-kit.sh
```

Label `NIXRECOVER` — wird beim Boot automatisch gemountet und eingelesen.

---

## Recovery — am q958

1. **reboot**
2. **Boot-Menü → USB `Q958RECOVER`** (nicht Festplatte, nicht „NixOS Install“ von anderem Stick)
3. **Bildschirm beobachten** — Banner „ZERO-TOUCH RECOVERY“
4. **Nichts tun** — e2fsck, Bootloader, Countdown 45s, Reboot
5. **USB-Stick(s) entfernen**
6. Normal von Festplatte booten → `ssh moritz@192.168.2.73`

---

## Fehler-Vorabfang (deklarativ)

| Risiko | Gegenmaßnahme |
|--------|---------------|
| Falsche Platte formatiert | `RECOVERY_DISK_BY_ID` + Verify vor e2fsck |
| `install` statt `recover` | Auto-Pfad nur `recover`; install braucht `INSTALL_CONFIRM=destroy` |
| Von kaputtem Root gebootet | `abort_if_running_from_broken_root` |
| USB = Systemplatte sda | `prepare-recovery-kit.sh` verweigert sda + by-id Check |
| Langer curl auf TTY | Nicht nötig — Skripte in ISO |
| Vergessene Befehle | Ein Service startet alles |
| Netz nötig | Nein — recover arbeitet offline auf Platte |
| profile.local verloren | Optional `NIXRECOVER`-Stick |

---

## Fallback (wenn Custom-ISO-Build scheitert)

Daten-USB ohne ISO-Build:

```bash
sudo RECOVERY_YES=1 RECOVERY_DATA_DEV=/dev/sdc bash scripts/prepare-recovery-kit.sh
```

Dann: Stock NixOS Minimal ISO + am Live-System:

```bash
mount /dev/disk/by-label/NIXRECOVER /mnt && bash /mnt/recover
```

Siehe [GUIDE-recovery-live-ssh.md](GUIDE-recovery-live-ssh.md).

---

## Dateien

| Datei | Rolle |
|-------|-------|
| `machines/q958/recovery-constants.nix` | Deklarative Konstanten |
| `machines/q958/recovery-iso.nix` | Custom Live-ISO + Auto-Service |
| `machines/q958/recovery-kit.env.example` | Vorlage für dein Kit |
| `scripts/prepare-recovery-kit.sh` | Kit bauen (non-interactive) |
| `scripts/build-recovery-iso.sh` | Nur ISO bauen |
| `scripts/lib/recovery-manifest.sh` | Manifest laden + Disk-Verify |
| `scripts/emergency-bootstrap-q958.sh` | recover-Logik |

---

## Nach erfolgreicher Recovery

1. SSH → MOTD / secrets-portal
2. `sudo nixos-rebuild-safe.sh switch` (Mensch)
3. Umbenennung `operator` — separates Ticket
