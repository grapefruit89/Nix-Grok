---
meta:
  role: doc
  purpose: Post-Recovery Checkliste — vor USB-Reboot anlegen, überlebt auch Fehlschlag
  date: 2026-07-12
  status: open
  tags:
    - recovery
    - todo
    - post-recovery
---

# Post-Recovery TODO (q958)

> **Angelegt vor USB-Recovery 2026-07-12.** Wenn Recovery scheitert: diese Liste bleibt auf GitHub.

## Sofort nach erfolgreichem Boot von Festplatte

- [ ] `ssh moritz@192.168.2.73` — geht SSH?
- [ ] `sudo nixos-rebuild-safe.sh switch` — aktiviert Guards, welcome-banner, disko-defense
- [ ] `systemctl status q958-auto-recover` — darf **nicht** laufen (war nur Live-ISO)
- [ ] `sudo dumpe2fs /dev/sda2 | head -5` — primärer Superblock OK?
- [ ] `ls /nix/var/nix/profiles/system-* | wc -l` — Generationen noch da?
- [ ] USB-Stick **raus** lassen bis q958 stabil bootet

## Identity-Refactor (eigenes Ticket)

- [ ] `moritz` → **`jarvis`** (oder finaler Kurzname) — Nix + `usermod -l`
- [ ] `users/moritz/` → `users/jarvis/`
- [ ] Locale/Domain in `users/jarvis/preferences.nix` + `profile.nix`
- [ ] `machines/q958/default.nix` — dynamisch `identity.user`
- [ ] `nixos`-Break-Glass-User **entfernen** (nur `jarvis` + root-tty)
- [ ] Trap-Skripte `/home/moritz` → `/home/jarvis`
- [ ] Docs: `ssh jarvis@…` statt moritz

## Impermanence (Stufe 9, später)

- [ ] `/persist`-Partition planen + Migration
- [ ] `rollout.stufe = 9` nur wenn bereit
- [ ] `/home/jarvis` nur Home-Manager — kein persistierter Müll

## Service-Daten → S3 (nicht Git)

- [ ] Restic S3-Creds in secrets-portal / profile.local
- [ ] Backup-Job testen
- [ ] Restore-Skript für Neuinstall (Jellyfin, HA, MQTT, …)

## Optional / Nice

- [ ] `git pull` auf q958 — auf `origin/main` @ `c4e030c` oder neuer
- [ ] `emergency/disko-accident-2026-07-12` Branch löschen
- [ ] Zweiter USB `NIXRECOVER` mit profile.local-Spiegel

---

## Wenn Recovery fehlschlägt

1. **Nicht** `disko install` / `mkfs.ext4`
2. USB wieder booten — `recover` ist idempotent
3. SSH: `root@192.168.2.73` / `recover` → `journalctl -fu q958-auto-recover`
4. Diese Datei auf GitHub lesen — Plan B steht hier