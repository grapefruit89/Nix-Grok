# ADR-023: Backup-Philosophie — Nur Unwiederbringliches sichern

**Status:** Accepted  
**Datum:** 2026-06-30

---

## Kontext

Ein NixOS-Homelab hat drei Datenkategorien die grundsätzlich verschieden behandelt werden müssen:
Deklarative Konfiguration, unwiederbringliche Anwendungsdaten, und regenerierbare Massendaten.

## Entscheidung

**Grundsatz: Nur sichern was man nicht wieder neu erzeugen oder herunterladen kann.**

### Was gesichert wird (Tier A → S3 via Restic)

| Daten | Warum | Service |
|-------|-------|---------|
| `/var/lib/secrets` | Encryption keys, API-Tokens — verloren = Systemausfall | systemd |
| `/var/lib/postgresql` | Linkwarden-Daten, künftig Immich-Metadaten | postgresql |
| `/var/lib/vaultwarden` | Passwort-Datenbank — absolut kritisch | vaultwarden |
| `/var/lib/pocket-id` | Passkey-Registrierungen, OIDC-Clients | pocket-id |
| `/var/lib/paperless` | Gescannte Dokumente — **unwiederbringlich** | paperless |
| `/var/lib/hass` | Home-Assistant-Automatisierungen, Historie | home-assistant |
| `/var/lib/zigbee2mqtt` | Zigbee-Pairings, Device-Config | zigbee2mqtt |
| `/var/lib/audiobookshelf` | Hörbuch-Fortschritt, Lesezeichen, Playlists | audiobookshelf |
| `/var/lib/technitium-dns-server` | DNS-Zonen, Blocklists-Konfiguration | technitium |
| `/var/lib/grafana` | Selbst erstellte Dashboards | grafana |

### Was explizit NICHT gesichert wird

| Daten | Warum nicht |
|-------|-------------|
| Tier C Medien (Filme, Serien, Musik) | Re-downloadbar von Usenet, zu groß (100+ GB) |
| Jellyfin-Thumbnails, MediaCover | Regenerierbar durch Jellyfin-Scan |
| Paperless-Thumbnails + Preview-Archive | Regenerierbar aus Originalen |
| Paperless Whoosh-Index | Regenerierbar (`document_index --reindex`) |
| `/etc/nixos` | Steht auf GitHub — Restic-Backup wäre redundant und kostet S3-Space |
| Caches, Logs, temporäre Dateien | Per Definition flüchtig |
| Crowdsec Hub-Daten | Re-downloadbar von `hub.crowdsec.net` |

### Immich (zukünftig)

Foto-Originale sind zu groß für ein Free-S3-Bucket (10GB Limit bei Cloudflare R2 / Backblaze B2).

**Strategie wenn Immich kommt:**
- Immich-DB (PostgreSQL) → bereits im Backup über `/var/lib/postgresql`
- Foto-Originale → **NICHT via Restic/S3** — zu teuer
- Foto-Originale → Lokale Redundanz: externes HDD oder zweite interne Platte
- Optional: rsync auf Freunde-/Familie-Server als off-site Kopie

## Backup-Parameter

```
Retention: --keep-daily 7 --keep-weekly 4
Verschlüsselung: Restic native (ChaCha20-Poly1305)
Ziel: S3-kompatibel (Cloudflare R2 / Backblaze B2 — Free Tier 10GB)
Frequenz: Täglich 03:00 Uhr
Service-Stop: Apps + DBs werden vor Backup gestoppt, danach neu gestartet
Dead Man's Switch: healthcheckUrl → Ping bei Erfolg, /fail bei Fehler
```

## Größenschätzung

| Daten | Rohgröße | Restic nach Deduplizierung |
|-------|----------|---------------------------|
| Secrets | ~1 MB | ~0.5 MB |
| Vaultwarden | ~5 MB | ~2 MB |
| Pocket-ID | ~5 MB | ~2 MB |
| Paperless (100 Dokumente) | ~500 MB | ~200–400 MB |
| Paperless (1000 Dokumente) | ~5 GB | ~2–4 GB |
| Rest (Grafana, HA, etc.) | ~100 MB | ~50 MB |
| **Gesamt (ohne große Paperless-Sammlung)** | ~700 MB | **~300 MB** |

→ Passt komfortabel in 10GB Free Tier, auch mit mehreren Wochen Retention.

## Links

- `modules/30-storage/30-storage.nix` — Implementierung
- F-009 in `docs/learnings/FINDINGS-REGISTRY.md`
- [ADR-022](022-no-raid-distance-parity.md) — warum kein lokales RAID
