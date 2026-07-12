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

## Was du brauchst

| Item | Details |
|------|---------|
| USB-Stick | [NixOS Minimal ISO](https://nixos.org/download.html) gebootet |
| Netz | q958 per Kabel an LAN (empfohlen) |
| Hauptrechner | SSH-Client, gleiches LAN |
| Optional | USB mit Backup von `profile.local.nix` |

---

## Phase 1 — q958 bootet Live-ISO (am Gerät oder per KVM)

1. NixOS Minimal ISO von USB starten
2. Im Boot-Menü: **NixOS - Install** (Live-System, RAM only)
3. An der **physischen Konsole** (tty) einloggen: User **`root`**, Passwort leer (Enter)

---

## Phase 2 — Netz + SSH aktivieren (Konsole am q958)

```bash
# Netz prüfen (Interface laut profile: eno1)
ip -4 addr show eno1

# Falls keine IP: DHCP sollte automatisch laufen.
# Sonst statisch (Beispiel — IP frei wählen, nicht 192.168.2.73 wenn alter Server noch läuft):
# ip addr add 192.168.2.99/24 dev eno1
# ip link set eno1 up
# ip route add default via 192.168.2.1

# SSH-Server starten (Live-ISO)
systemctl start sshd
systemctl status sshd --no-pager

# Root-Passwort setzen (nur für Live-System, temporär)
passwd root
```

Notiere die IP: z.B. `192.168.2.x` aus `ip -4 addr show eno1`.

---

## Phase 3 — Vom Hauptrechner per SSH

Am Live-ISO ist nur **root** mit Passwort relevant — dein normaler Key-Login (`moritz@192.168.2.73`) gilt **nicht** auf dem Installer.

### Schritt für Schritt (Hauptrechner)

```bash
# 1) Erreichbarkeit prüfen (INSTALLER_IP aus Phase 2)
ping -c 2 INSTALLER_IP

# 2) Einloggen — temporäres root-Passwort von Phase 2
ssh root@INSTALLER_IP

# Beispiel wenn q958 per DHCP .99 bekam:
# ssh root@192.168.2.99
```

Beim ersten Mal: Host-Key mit `yes` bestätigen, dann root-Passwort eingeben.

### Copy-Paste-Block (Recovery komplett per SSH)

Nach `ssh root@INSTALLER_IP` auf dem Live-System:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/grapefruit89/Nix-Grok/master/scripts/emergency-bootstrap-q958.sh \
  | bash -s recover
```

Wichtig: **`bash -s recover`** (nicht `sudo bash recover`). Auf dem Live-ISO bist du bereits root.

### Optional: SSH-Config auf dem Hauptrechner

In `~/.ssh/config` auf dem PC, damit du die IP nicht tippen musst:

```
Host q958-recover
    HostName INSTALLER_IP
    User root
    StrictHostKeyChecking accept-new
```

Dann: `ssh q958-recover`

### Hinweis zu „PSSH“ / parallel-ssh

Für **eine** Maschine reicht normales `ssh` — kein `pssh` nötig. `parallel-ssh` lohnt sich erst bei mehreren Hosts gleichzeitig; beim Recovery arbeitest du nur auf dem Live-ISO des q958.

---

## Phase 4 — Recovery ausführen (auf Live-System, per SSH oder Konsole)

```bash
curl -fsSL \
  https://raw.githubusercontent.com/grapefruit89/Nix-Grok/master/scripts/emergency-bootstrap-q958.sh \
  | bash -s recover
```

Oder älterer getesteter Branch:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/grapefruit89/Nix-Grok/emergency/disko-accident-2026-07-12/scripts/emergency-bootstrap-q958.sh \
  | bash -s recover
```

### Was `recover` macht (automatisch)

1. **`e2fsck -b <backup-sb>`** auf `/dev/sda2` — ext4 reparieren
2. Mount `/dev/sda2` → `/mnt`, ESP neu **vfat** `NIXBOOT` → `/mnt/boot`
3. **`switch-to-configuration boot`** vom letzten `system`-Profil in `/mnt/nix/var/nix/profiles/system`

→ Gleicher Store, gleiche Generationen.

### Optional: profile.local.nix vom USB

```bash
# USB mounten, dann vor recover oder wenn Skript es findet:
mount /dev/disk/by-label/NIXUSB /media/moritz  # Label anpassen
cp /media/moritz/profile.local.nix /mnt/etc/nixos/machines/q958/
```

---

## Phase 5 — Reboot

```bash
reboot
```

Festplatte booten (USB entfernen). System sollte wie vor dem Unfall starten.

---

## Phase 6 — Nach Boot

1. SSH: `ssh moritz@192.168.2.73` (normaler Key-Login)
2. **MOTD zeigt secrets-portal** — externe Secrets setzen
3. `sudo nixos-rebuild-safe.sh switch` (Mensch) — voller nix-Guard aktiv

---

## Fehlerbehebung

| Problem | Lösung |
|---------|--------|
| `sshd` startet nicht | Konsole nutzen, Recovery direkt am tty |
| Keine IP | Kabel/Port prüfen, `systemctl status systemd-networkd` |
| `e2fsck` schlägt fehl | **Nicht** `install` ohne Backup-Plan — Datenrettung-Dienst |
| SSH vom PC geht nicht | Firewall am Hauptrechner? Gleiches Subnetz? Ping testen |

---

## Siehe auch

- [EMERGENCY-RECOVERY.md](../EMERGENCY-RECOVERY.md)
- [GUIDE-cold-start.md](GUIDE-cold-start.md) — Neuinstall statt recover
