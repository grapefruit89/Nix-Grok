# ADR-042: Offline-Anchors & Evil Maid Protection

## Status
**Proposed** (Langzeit-Ziel)

## Kontext
Im Rahmen des Architektur-Audits (Pattern Mining) wurden zwei hochkritische Zero-Trust Vektoren identifiziert, die über eine Standard-Absicherung hinausgehen:

1. **SOPS Deadlock:** Wenn alle Emergency-Keys für die SOPS-Entschlüsselung (AGE) ausschließlich in Online-Systemen (wie Bitwarden) gespeichert sind, droht ein "Zirkelschluss". Wenn das lokale Netzwerk, der DNS-Server oder der Reverse-Proxy ausfällt, ist der Passwortmanager oft nicht erreichbar. Ohne Passwortmanager kein AGE-Key, und ohne AGE-Key kein Server-Rebuild zur Reparatur.
2. **Evil Maid Angriffe:** Die Festplattenverschlüsselung (LUKS) ist an das TPM2-Modul (PCR 0,1,2,3,7) gebunden. Das schützt gegen Festplattendiebstahl. Wenn ein physischer Angreifer ("Evil Maid") jedoch den Bootloader oder den Kernel auf der unverschlüsselten EFI-Partition austauscht, wird LUKS immer noch entsperrt und der kompromittierte Bootloader kann das Root-Passwort abgreifen.

## Entscheidung
Wir dokumentieren diese Vektoren hier in der Single Source of Truth (SSoT), um sie in der Zukunft anzugehen.

### 1. Offline-Anchor Pflicht (SOPS)
- **Regel:** Es muss zwingend ein Stateless Offline-Rettungsanker existieren.
- **Lösung:** Der Master AGE-Key wird auf einen verschlüsselten USB-Stick kopiert und physisch sicher verwahrt (Schlüsselbund / Tresor). Online-Backups dienen nur der Bequemlichkeit.

### 2. Full TPM-Sealing (Evil Maid)
- **Lösung:** Langfristig muss LUKS an PCR 4 (Bootloader) und PCR 9 (Kernel/Initrd) gebunden werden.
- **Problem:** NixOS ändert den Kernel und die Initrd bei jedem Rebuild.
- **Architektur:** Nutzung von `systemd-cryptenroll --tpm2-public-key`. Dem TPM-Chip wird nicht mehr nur ein statischer Hash, sondern ein kryptografisches Zertifikat übergeben. Das System signiert die neue Initrd/Kernel bei jedem Rebuild automatisch, sodass das TPM auch nach einem Update sicher entschlüsselt, aber fremde (unsignierte) Kernel blockiert.

## Konsequenzen
- **Aktuell:** Diese Änderungen erfordern tiefgreifende Eingriffe in die Boot-Phase und das SOPS-Management. Sie werden aus pragmatischen Gründen vorerst zurückgestellt.
- **Zukunft:** Dieser ADR dient als Vorlage für KIs, sobald der Server stabil läuft und in die Hochsicherheits-Phase (Stufe 3) eintritt.
