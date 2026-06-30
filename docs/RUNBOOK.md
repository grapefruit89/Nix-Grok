---
meta:
  role: runbook
  purpose: Bekannte Fehler + Quick-Fixes — erste Anlaufstelle für Alert-Script und KI-Triage
  tags:
    - runbook
    - errors
    - monitoring
---

# Runbook — q958 Homelab {#runbook}

> **Erste Anlaufstelle** für bekannte Fehlermuster. Alert-Script und KI-Triage suchen hier zuerst.
> Neuen Fehler beheben? → neue Zeile in [Schnellreferenz](#quick-ref) + ggf. neue ADR.

---

## Schnellreferenz — alle bekannten Fehler {#quick-ref}

| error_pattern | Service | Quick-Fix | ADR |
|---|---|---|---|
| `strconv\.Atoi.*invalid syntax` | caddy | `ip_mask 24` statt `/24` | [018](adr/018-caddy-dual-log-dsgvo.md) |
| `Failed to load environment files` | lidarr, readarr | `sudo touch /var/lib/secrets/<name>.env && sudo chmod 600 ...` | — |
| `cannot change owner.*not permitted` | jellyfin | `systemd.tmpfiles.rules` statt `install -d -o` | — |
| `Failed to set up mount namespacing` | arr-apps | BindPaths-Ziel + Quellverzeichnis anlegen | — |
| `KeyError.*discovery_keys\|subentries` | home-assistant | `sudo rm -rf /var/lib/hass/* && systemctl restart home-assistant` | — |
| `OOM.*\|killed.*process.*jellyfin` | jellyfin | `MemoryMax` in memory-policy.nix erhöhen | [003](adr/003-oom-cgroup-isolation.md) |

---

## Caddy {#caddy}

### ip_mask Syntaxfehler → Endlosloop {#caddy-ip-mask}

**error_pattern:** `strconv\.Atoi.*invalid syntax`

```bash
journalctl -u caddy -n 20 --no-pager | grep -i error
# Erwarteter Output:
# Error: adapting config using caddyfile: error parsing ip_mask /24: strconv.Atoi: ...
```

**Ursache:** Caddyfile erwartet `ip_mask 24`, nicht `/24` (kein Slash).

**Fix:**
```bash
# In modules/10-network/11-network.nix:
#   ip_mask /24  →  ip_mask 24
#   ip_mask /48  →  ip_mask 48
grep -rn "ip_mask" /etc/nixos/modules/
# Dann:
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
# und in tmux: sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure
```

**Verwandt:** [ADR-018 — Caddy Dual-Log DSGVO](adr/018-caddy-dual-log-dsgvo.md)

---

## Arr-Apps (Lidarr, Readarr, Sonarr, Radarr, Prowlarr) {#arr-apps}

### Fehlende .env-Datei {#arr-env-missing}

**error_pattern:** `Failed to load environment files`

```
systemd[1]: lidarr.service: Failed to load environment files: /var/lib/secrets/lidarr.env
```

**Fix:**
```bash
for name in lidarr readarr sonarr radarr prowlarr; do
  f="/var/lib/secrets/$name.env"
  sudo bash -c "[ -f '$f' ] || (echo '# $name secrets' > '$f' && chmod 600 '$f')"
done
sudo systemctl restart lidarr readarr sonarr radarr prowlarr
```

### BindPaths-Ziel fehlt {#arr-bindpaths}

**error_pattern:** `Failed to set up mount namespacing`

```
systemd[1]: lidarr.service: Failed to set up mount namespacing: /var/lib/lidarr/MediaCover: No such file or directory
```

**Ursache:** `BindPaths` in systemd braucht BEIDE Seiten (Quelle + Ziel). Auf Neuinstallation existiert `/var/lib/<name>/MediaCover` noch nicht.

**Fix:**
```bash
NAME=lidarr  # anpassen
sudo mkdir -p /mnt/fast_pool/metadata/$NAME /var/lib/$NAME/MediaCover
sudo chown ${NAME}:media /mnt/fast_pool/metadata/$NAME
sudo chmod 0775 /mnt/fast_pool/metadata/$NAME
sudo chown ${NAME}:${NAME} /var/lib/$NAME/MediaCover
sudo systemctl restart $NAME
```

**Dauerhafter Fix (NixOS-Config):** `arr-helper.nix` enthält seit 2026-06-29 `systemd.tmpfiles.rules` für beide Verzeichnisse — wirkt nach nächstem `nixos-rebuild switch`.

---

## Jellyfin {#jellyfin}

### CAP_CHOWN fehlt im preStart {#jellyfin-chown}

**error_pattern:** `cannot change owner.*not permitted\|install.*cannot change owner`

```
install: cannot change owner of '/var/lib/jellyfin/config': Operation not permitted
```

**Ursache:** `CapabilityBoundingSet = lib.mkForce ""` in `lib/service-factory.nix:50` entfernt alle Capabilities inkl. CAP_CHOWN. `install -d -o jellyfin` schlägt fehl.

**Fix (NixOS-Config):**
```nix
# In jellyfin.nix: systemd.tmpfiles.rules statt install -d -o im preStart
systemd.tmpfiles.rules = [
  "d /run/jellyfin-transcode 0750 jellyfin jellyfin -"
  "d /mnt/fast_pool/metadata/jellyfin 0750 jellyfin media -"
];
# preStart: install -d -m 0750 -o jellyfin → mkdir -p (ownership via tmpfiles)
```

**tmpfiles** läuft als root nach `local-fs.target`, vor dem Service — setzt Ownership korrekt.

**Verwandt:** `lib/service-factory.nix:50` — `CapabilityBoundingSet`

---

## Home Assistant {#home-assistant}

### Core-Config-Korruption / KeyError {#ha-corruption}

**error_pattern:** `KeyError.*discovery_keys\|subentries.*not.*defined`

```
homeassistant.core - ERROR - Error loading config entry ... KeyError: 'discovery_keys'
```

**Fix (Dev-System — keine Daten zu behalten):**
```bash
sudo systemctl stop home-assistant
sudo rm -rf /var/lib/hass/*
sudo systemctl start home-assistant
# HA startet auf aktueller Version (2026.5.4) mit leerer Config
```

**Ursache:** Alte Config-Format-Version nicht kompatibel mit neuer HA-Version. Auf Dev-System ist Wipe die schnellste Lösung.

---

## Diagnosebefehle — Schnellreferenz {#diagnose}

```bash
# Service-Status + letzte Fehler
systemctl status <service> --no-pager
journalctl -u <service> -n 50 --no-pager | grep -iE "error|fail|warn|except"

# Alle gecrashteten Services
systemctl list-units --state=failed

# error_pattern aus ADRs gegen journalctl matchen
ERROR=$(journalctl -u caddy -n 5 --no-pager | tail -1)
grep -r "error_pattern:" /etc/nixos/docs/adr/ | while IFS=: read -r file key val; do
  pattern="${val//\"/}"
  echo "$ERROR" | grep -qP "$pattern" && echo "Match: $file"
done

# Ressourcen pro Service
systemd-cgtop -n1

# OOM-Checks
journalctl -k | grep -i "oom\|killed process"

# Alle Services die Neustart geloopt haben
journalctl -b --no-pager | grep "Start request repeated too quickly"
```

---

## Verwandt {#siehe-auch}

- [ADR-Index](adr/README.md) — Architecture Decision Records
- [CLAUDE-GUIDE](adr/CLAUDE-GUIDE.md) — Markdown-Funktionen für KI-Nutzung
- [Globales TOC](TOC.md) — alle Anker aller Dokumente (`sudo bash /etc/nixos/scripts/gen-toc.sh`)
- [ADR-003 — OOM-Isolation](adr/003-oom-cgroup-isolation.md)
- [CLAUDE.md](/etc/nixos/CLAUDE.md) — aktiver System-Zustand + TODOs
