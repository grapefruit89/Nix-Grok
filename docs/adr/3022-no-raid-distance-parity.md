---
meta:
  role: doc
  purpose: Keine lokale Redundanz — geografische Distanz statt RAID
  status: accepted
  date: 2026-06-30
  tags:
    - storage
    - raid
    - backup
---
# ADR-3022: Keine lokale Redundanz — Geografische Distanz statt RAID {#adr-3022-keine-lokale-redundanz-geografische-distanz-statt-raid}

**Quelle:** Knowledge-Base ADR-015 (Distance Parity Mandate)
---

## Kontext {#kontext}

Klassische Homelab-Setups verwenden RAID oder SnapRAID zur lokalen Festplatten-Redundanz. Die Überlegung: schützt vor einzelnem Festplattenausfall ohne Datenverlust.

## Entscheidung {#entscheidung}

**Kein RAID, kein SnapRAID, keine Parität auf Tier C.**

Stattdessen:

| Tier | Daten | Schutz-Strategie |
|------|-------|------------------|
| A (Persistenz) | Secrets, DBs, Config | Restic → S3 (geografisch entfernt) |
| A++ (Fotos) | Persönliche Fotos | 3-2-1: lokal + 2 Cloud-Standorte |
| C (Medien) | Filme, Serien | Kein expliziter Schutz — re-downloadbar |

## Begründung {#begruendung}

### Warum kein RAID {#warum-kein-raid}

1. **Schützt nicht gegen die echten Risiken** — RAID hilft bei Festplatten-HW-Fehler. Es schützt nicht gegen:
   - Feuer / Überschwemmung (lokal-katastrophisch)
   - Diebstahl (lokal-katastrophisch)
   - Ransomware / Bit-Rot (cascade)
   - Menschliches Versagen (file delete)

2. **Komplexitätskosten** — RAID-Degraded-Zustand erfordert Monitoring, Replace-Prozedur, Rebuild (Stunden-/Tage-lang erhöhtes Ausfallrisiko)

3. **Spindown verhindert** — RAID-Arrays halten alle Member-Disks spinning. Nix-Grok nutzt hd-idle für Tier-C Spindown → inkompatibel

4. **MergerFS ist kein RAID** — MergerFS aggregiert Kapazität ohne Parität. Das ist gewollt: einfaches Jbod-Pooling, kein RAID-Versprechen.

### Warum Tier-C Verlust akzeptierbar {#warum-tier-c-verlust-akzeptierbar}

Tier-C enthält Medien (Filme, Serien, Musik) die von Usenet/Internet re-abrufbar sind. Der Wiederherstellungswand ist Bandbreite + Zeit, nicht Datenverlust.

### Tier-A unter 10 GB halten {#tier-a-unter-10-gb-halten}

Damit Restic-Backups schnell und günstig bleiben:
- Logging: begrenzt via `SystemMaxUse=1G`
- Thumbnails: extern (Jellyfin/Scrutiny) via `extraPaths` nicht in Tier-A
- State: nur kritische DBs (postgresql, vaultwarden, pocket-id)

## Links {#links}

- `modules/30-storage/30-storage.nix` — MergerFS-Konfiguration (kein RAID)
- `modules/30-storage/30-storage.nix` — Restic-Backup (Tier A offsite)
- `modules/30-storage/36-disk-health.nix` — hd-idle Spindown
- Knowledge-Base `adr/ADR-015-Distance-Parity-Mandate.md` — Originalfund

## Siehe auch {#siehe-auch}

- [ADR-3023 — Backup-Philosophie](3023-backup-philosophy.md)
- [GUIDE-storage-tiers](../guides/GUIDE-storage-tiers.md)
