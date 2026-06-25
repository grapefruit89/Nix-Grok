---
meta:
  role: doc
  purpose: Session-Log Review-Fixes 2026-06-17
  tags:
    - session
    - changelog
---

# Session 2026-06-17 — Review-Fixes & Pre-Rebuild Hardening

Dokumentation aller Änderungen aus der Claude-Review-Session und dem anschließenden
Rebuild auf q958 (Rollout **Stufe 8**).

**Commits:** `35bf139` → `2d7af29` auf `main`  
**Rebuild:** `sudo tools/rebuild-q958.sh` — erfolgreich, Generation `system-93-link`

---

## Ausgangslage

- Claude-Review-Prompt angelegt: `claudereview_prompt.md` (batched, idempotent)
- Mehrere Claude-Review-Durchläufe mit vielen False Positives; ein späterer Durchlauf
  (REV-001–REV-008) war substanziell brauchbar
- Offene Lücken: kaputte Flake-Targets, Impermanence-Konflikt, Secrets-Hygiene,
  Restic ohne S3, Doc-Drift, Legacy-Dateien

---

## Commit `35bf139` — Claude Review Findings (REV-001–008)

### REV-008 (high) — Kaputte Flake-Konfigurationen

- `laptop` und `wsl` aus `flake.nix` entfernt (`hosts/` existierte nicht)
- Input `nixos-wsl` entfernt, `flake.lock` aktualisiert
- Flake-Beschreibung auf Q958 Homelab fokussiert

### Impermanence (high, vor Stufe 9)

- `storage.impermanence.mountPoint = "/persist"` in `machines/q958/profile.nix`
- `default.nix` verdrahtet Impermanence auf `/persist`, nicht auf `/`
- `hardware.nix` behält `/` auf NIXPERSIST für Stufe 0–8

### REV-002 (medium) — Hardcoded Dev-Passwort

- Hardcoded AMP-Dev-Passwort-Fallback aus `machines/q958/secrets.nix` entfernt
- `amp.adminPassword` muss in `profile.local.nix` stehen (Nix-`throw` beim Build)

### REV-004 (medium) — `verify-no-secrets.sh`

- Regex erweitert: `$y$`, `$argon2id$` etc. (`\$[a-zA-Z0-9]`)
- `claudereview_prompt.md` von grep ausgenommen (kein False Positive)
- `docs/SECURITY.md` verweist jetzt direkt auf das Script

### REV-003 (medium) — Restic Healthcheck

- `restic.healthcheckUrl` aus `profile.nix` nach `profile.local.nix` (top-level `restic`)
- `profile.local.nix.example` ergänzt

### Restic S3-Provision (fehlte im Review)

- `secrets.restic` in `profile.local.nix.example` (repository, AWS-Keys)
- `secrets.nix` erzeugt `/var/lib/secrets/restic_s3_creds` nur wenn `repository` gesetzt

### REV-001 (medium) — Doc-Drift

- `docs/ROADMAP.md`: aktuell **Stufe 8** (nftables, CrowdSec, fail2ban)

### REV-005 (medium) — Legacy / Duplikate gelöscht

| Datei | Grund |
|-------|-------|
| `00-core.nix` (root) | Duplikat von `modules/00-core.nix` |
| `kernel-slim-q958.nix` | Legacy |
| `flake-q958.patch.nix` | ungenutzt |
| `hosts-q958-redirect.nix` | ungenutzt |
| `patch-00-core.py` | ungenutzt |
| `machines/q958/dienste-stufen.nix` | Legacy-Duplikat von `rollout.nix` |
| `machines/q958/zugang-sicherung.nix` | Legacy |
| `modules/30-storage.nix.snapshot-*` | Snapshot-Backup |

`deploy-machines-q958.sh`: `rm`-Einträge für gelöschte Dateien bereinigt

### REV-006 (low) — Firewall-Host-Werte

- `security.firewall` in `machines/q958/profile.nix` (`lanCidrs`, `blockedCountries`, `allowLanDns`)
- Verdrahtung in `machines/q958/default.nix` → `my.security.firewall`

### REV-007 (low) — Restic Healthcheck bei Fehler

- `modules/30-storage.nix`: bei Backup-Fehler Ping an `…/fail`, bei Erfolg normale URL

---

## Commit `2d7af29` — Pre-Rebuild Hardening

### Restic nur mit S3

- `restic.offsiteEnable` in `profile.nix` (true wenn `secrets.restic.repository != ""`)
- `rollout.nix`: `restic-backup.enable` nur wenn `offsiteEnable` + Stufe ≥ 6
- Ohne S3: kein Restic-Timer (verhindert fehlschlagende Services)

### Strikte Secrets-Pflicht

- `profile.nix`: kein leerer Fallback mehr → `throw` wenn `profile.local.nix` fehlt

### Stufe 9 vorbereitet

- Boot-Menü ab Stufe 9: `Production (Impermanence)`, `sortKey = 9_production`
- Assertion: `impermanence.mountPoint` darf bei Stufe 9 nicht `/` sein

### Rebuild-Pipeline verbessert (`tools/rebuild-q958.sh`)

1. Prüft `profile.local.nix` existiert
2. `verify-no-secrets.sh`
3. rsync `/home/nixos` → `/etc/nixos` (exkl. `.git`, `stage-nixos/`, …)
4. `profile.local.nix` mit mode 600 nach `/etc/nixos`
5. `nixos-rebuild build` dann `switch`
6. `post-switch-check.sh`

### Git-Hook

- `tools/install-git-hooks.sh` → pre-push führt `verify-no-secrets.sh` aus

### Weitere Bereinigung

- `configuration.bootstrap.nix` entfernt (Legacy)

---

## Rebuild-Ergebnis (17.06.2026)

```text
Rollout: stufe = 8
Generation: system-93-link
```

**Aktiv nach Switch:**

- Kern: caddy, blocky, pocket-id, postgresql, valkey, tailscaled
- Observability: gatus, loki, grafana, vector
- Media: jellyfin, sonarr, radarr, prowlarr, sabnzbd
- Security: nftables, crowdsec, fail2ban, crowdsec-firewall-bouncer

**Bewusst gestoppt:** `restic-backups-tier-a-sovereign.timer` (kein S3-Repository konfiguriert)

---

## Bewusst noch offen

| Thema | Nächster Schritt |
|-------|------------------|
| S3-Offsite-Backup | `secrets.restic.repository` + AWS-Keys in `profile.local.nix`, dann rebuild |
| Cloudflare / Fritzbox DNS | siehe `docs/ROADMAP.md` Checkliste |
| Dev-Keys rotieren | vor Production (Stufe 9) — siehe `docs/SECURITY.md` |
| SOPS | erst Stufe 9+ / Production — nicht anfassen |
| Home Assistant Core-Dump | im Journal (vorher existierend), separat debuggen |
| `stage-nixos/` | lokal/gitignored, nicht im Remote |

---

## Nützliche Befehle

```bash
# Standard-Rebuild (Pre-checks + build + switch + Service-Check)
sudo tools/rebuild-q958.sh

# Secrets-Check manuell
bash tools/verify-no-secrets.sh

# Git pre-push Hook installieren
bash tools/install-git-hooks.sh

# Flake bauen (auf dem Server mit profile.local.nix unter /etc/nixos)
sudo nixos-rebuild build --flake /etc/nixos#q958 --impure
```

---

## Referenzen

- Review-Prompt: `claudereview_prompt.md`
- Architektur: `AGENTS.md`
- Rollout-Übersicht: `README.md`, `docs/ROADMAP.md`
- Secrets: `docs/SECURITY.md`, `machines/q958/profile.local.nix.example`