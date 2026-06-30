# ADR-022: Keine lokale Redundanz — Geografische Distanz statt RAID

**Status:** Accepted  
**Datum:** 2026-06-30  
**Quelle:** Knowledge-Base ADR-015 (Distance Parity Mandate)

---

## Kontext

Klassische Homelab-Setups verwenden RAID oder SnapRAID zur lokalen Festplatten-Redundanz. Die Überlegung: schützt vor einzelnem Festplattenausfall ohne Datenverlust.

## Entscheidung

**Kein RAID, kein SnapRAID, keine Parität auf Tier C.**

Stattdessen:

| Tier | Daten | Schutz-Strategie |
|------|-------|------------------|
| A (Persistenz) | Secrets, DBs, Config | Restic → S3 (geografisch entfernt) |
| A++ (Fotos) | Persönliche Fotos | 3-2-1: lokal + 2 Cloud-Standorte |
| C (Medien) | Filme, Serien | Kein expliziter Schutz — re-downloadbar |

## Begründung

### Warum kein RAID

1. **Schützt nicht gegen die echten Risiken** — RAID hilft bei Festplatten-HW-Fehler. Es schützt nicht gegen:
   - Feuer / Überschwemmung (lokal-katastrophisch)
   - Diebstahl (lokal-katastrophisch)
   - Ransomware / Bit-Rot (cascade)
   - Menschliches Versagen (file delete)

2. **Komplexitätskosten** — RAID-Degraded-Zustand erfordert Monitoring, Replace-Prozedur, Rebuild (Stunden-/Tage-lang erhöhtes Ausfallrisiko)

3. **Spindown verhindert** — RAID-Arrays halten alle Member-Disks spinning. Nix-Grok nutzt hd-idle für Tier-C Spindown → inkompatibel

4. **MergerFS ist kein RAID** — MergerFS aggregiert Kapazität ohne Parität. Das ist gewollt: einfaches Jbod-Pooling, kein RAID-Versprechen.

### Warum Tier-C Verlust akzeptierbar

Tier-C enthält Medien (Filme, Serien, Musik) die von Usenet/Internet re-abrufbar sind. Der Wiederherstellungswand ist Bandbreite + Zeit, nicht Datenverlust.

### Tier-A unter 10 GB halten

Damit Restic-Backups schnell und günstig bleiben:
- Logging: begrenzt via `SystemMaxUse=1G`
- Thumbnails: extern (Jellyfin/Scrutiny) via `extraPaths` nicht in Tier-A
- State: nur kritische DBs (postgresql, vaultwarden, pocket-id)

## Links

- `modules/30-storage/30-storage.nix` — MergerFS-Konfiguration (kein RAID)
- `modules/30-storage/30-storage.nix` — Restic-Backup (Tier A offsite)
- `modules/30-storage/36-disk-health.nix` — hd-idle Spindown
- Knowledge-Base `adr/ADR-015-Distance-Parity-Mandate.md` — Originalfund
