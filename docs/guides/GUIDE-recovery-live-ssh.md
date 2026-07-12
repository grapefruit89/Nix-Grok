---
meta:
  role: doc
  purpose: Recovery vom Live-USB — Schritt für Schritt inkl. SSH vom Hauptrechner
  date: 2026-07-12
  status: current
  tags:
    - recovery
    - ssh
    - live-usb
  docs:
    - docs/EMERGENCY-RECOVERY.md
---

# Recovery Live-USB — genau so (inkl. SSH vom Hauptrechner)

> Ziel: **recover** — Store + Generationen behalten. **Nicht** `install`.

---

## Der Reboot-Widerspruch — aufgelöst

| Verboten | Erlaubt / nötig |
|----------|-----------------|
| Reboot und **von der kaputten Festplatte** booten | Reboot und im **Boot-Menü den USB-Stick** wählen |
| `shutdown` und hoffen, dass es von selbst geht | Bewusst: **F12 / Boot-Menü → NixOS USB** |

**„Nicht rebooten“** heißt: nicht normal weiterarbeiten und irgendwann neu starten, als wäre nichts.
**Du musst einmal rebooten** — aber nur, um vom **Live-USB** zu starten, nicht von `sda`.

Ablauf in einem Satz: *Kaputtes System läuft noch → Recovery-USB vorbereiten → reboot →
USB booten → recover → reboot → Festplatte booten.*

---

## Drei Wege zum recover (kurz → lang)

### Weg A — Empfohlen: Hauptrechner + SSH (nichts Langes auf der TTY tippen)

1. **Jetzt**, solange q958 noch läuft: optional Daten-USB vorbereiten (siehe Weg B)
2. Reboot → Boot-Menü → **NixOS Minimal ISO**
3. Am q958 nur **vier kurze Befehle** auf der TTY:

```bash
systemctl start sshd
passwd root
ip -4 addr show eno1
```

4. **Am Hauptrechner** (hier Copy-Paste, nicht an der Server-TTY):

```bash
ssh root@INSTALLER_IP
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh | bash -s recover
```

Der lange `curl` läuft auf **deinem PC** in der SSH-Session — nicht an der Bildschirm-Tastatur.

### Weg B — Ohne Netz: Recovery-USB (zweiter Stick, **jetzt** vorbereiten)

**Solange das System noch läuft** (vor dem Reboot zum Live-ISO):

```bash
sudo bash /etc/nixos/scripts/prepare-recovery-usb.sh
```

Legt auf einen **zweiten** USB-Stick (`NIXRECOVER`):

- `recover` — Ein-Befehl
- `emergency-bootstrap-q958.sh`
- `profile.local.nix` (falls vorhanden)

Am Live-USB danach — **zwei kurze Zeilen**, kein curl:

```bash
mount /dev/disk/by-label/NIXRECOVER /mnt
bash /mnt/recover
```

### Weg C — Nur ein USB-Stick (ISO), mit Netz

Wie Weg A: Live-ISO booten, SSH vom Hauptrechner, `curl` dort einfügen.

---

## Was du brauchst

| Item | Details |
|------|---------|
| USB-Stick 1 | [NixOS Minimal ISO](https://nixos.org/download.html) |
| USB-Stick 2 (optional) | `prepare-recovery-usb.sh` — kein Tippen von URLs |
| Netz | Empfohlen für Weg A/C |
| Hauptrechner | SSH-Client, gleiches LAN |

---

## Phase 1 — Live-ISO booten

1. NixOS Minimal ISO starten (**Boot-Menü: USB, nicht sda**)
2. **NixOS - Install** (Live-System)
3. Konsole: **`root`**, Passwort leer (Enter)

---

## Phase 2 — Netz + SSH (nur für Weg A/C)

```bash
ip -4 addr show eno1
systemctl start sshd
passwd root
```

IP notieren → `INSTALLER_IP`.

---

## Phase 3 — Recovery ausführen

| Weg | Befehl |
|-----|--------|
| A/C (SSH) | `curl -fsSL …/emergency-bootstrap-q958.sh \| bash -s recover` |
| B (USB) | `mount /dev/disk/by-label/NIXRECOVER /mnt && bash /mnt/recover` |

**Nicht** `install`. **Nicht** `sudo bash recover` (Live-ISO = schon root).

### Was `recover` macht

1. `e2fsck -b <backup-sb>` auf `/dev/sda2`
2. Mount + ESP neu als vfat `NIXBOOT`
3. `switch-to-configuration boot` vom letzten system-Profil

→ Gleicher Store, gleiche Generationen.

---

## Phase 4 — Reboot (jetzt erlaubt)

```bash
reboot
```

**Beide USB-Sticks raus** (oder Boot-Menü: Festplatte). System sollte von `sda` starten.

---

## Phase 5 — Nach Boot

1. SSH: `ssh moritz@192.168.2.73` (normaler Key-Login)
2. MOTD → secrets-portal
3. `sudo nixos-rebuild-safe.sh switch` (Mensch)

---

## Fehlerbehebung

| Problem | Lösung |
|---------|--------|
| Bootet wieder kaputt | USB im Boot-Menü priorisieren; nach recover USB raus |
| Kein Netz | Weg B (`NIXRECOVER`-Stick) |
| Langer curl auf TTY | Weg A: SSH vom PC, oder Weg B |
| `e2fsck` schlägt fehl | Nicht `install` ohne Backup-Plan |

---

## Siehe auch

- [EMERGENCY-RECOVERY.md](../EMERGENCY-RECOVERY.md)
- [GUIDE-cold-start.md](GUIDE-cold-start.md)
