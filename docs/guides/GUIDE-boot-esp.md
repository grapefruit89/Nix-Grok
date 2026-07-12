---
meta:
  role: doc
  purpose: ESP/systemd-boot q958 — Größe, Generationen vs. Kernel, Optimierung
  date: 2026-07-12
  status: current
  docs:
    - machines/q958/profile.nix
    - docs/adr/3024-disko-tier-a-provisioning.md
  tags:
    - boot
    - esp
    - systemd-boot
---

# Boot & ESP (q958) {#guide-boot-esp}

## Kurzfassung {#kurz}

| Was | Größe / Verhalten |
|-----|-------------------|
| **ESP-Ziel** | **512 MB** (`profile.nix` → `storage.tierA.boot.espSize`) |
| **generationLimit** | Nur **Menü-Einträge** (~4 KB/Gen) — **nicht** ESP-Belegung pro Gen |
| **ESP-Wachstum** | Nur bei **neuer Kernel-Version** in nixpkgs (~45–50 MB Paar) |
| **Aktuelles Paar** | bzImage ~14 MB + initrd ~33 MB (zstd) ≈ **47 MB** |

Viele NixOS-Generationen (322–336) mit **gleichem** Kernel 7.0.10 → **ein** EFI-Paar, viele `.conf`-Zeiger.

---

## ESP-Größe: 512 MB reicht {#esp-512}

### Worst-Case (max. 2 Kernel-Versionen parallel, Production)

```text
2 Kernel-Paare × ~50 MB     ≈ 100 MB
Loader + Baseline           ≈   5 MB
Puffer (größere Initrds)    ≈ 100 MB
────────────────────────────────────
≈ 205 MB  <<  512 MB
```

### Szenarien

| Szenario | ESP | generationLimit | Anmerkung |
|----------|-----|-----------------|-----------|
| **Production (Ziel)** | 512 MB | 5–7 | Aufgeräumtes Menü |
| **Dev (jetzt)** | 512 MB | 15 | Viele Rollback-Einträge, **gleicher Speicher** solange Kernel gleich |
| Minimal + Aufräumen | 256 MB | 3–5 | Nur wenn ≤2 Kernel-Paare garantiert |

**1 GB** lohnt nur bei Dual-Boot oder vielen parallelen Kernel-Major-Versionen — für reinen NixOS-Server Verschwendung.

SSoT: `machines/q958/profile.nix` → `storage.tierA.boot.espSize = "512M"`.

---

## Was liegt auf der ESP? {#esp-inhalt}

systemd-boot (NixOS) kopiert bei **neuer Kernel-Version** ein Paar nach `/boot/EFI/nixos/`:

| Datei | ~Größe | Was ist das? |
|-------|--------|--------------|
| `*-linux-X.Y.Z-bzImage.efi` | ~14 MB | Linux-Kernel als **EFI PE/COFF** (CONFIG_EFI_STUB) — bootbar ohne separates GRUB |
| `*-initrd-linux-X.Y.Z-initrd.efi` | ~33 MB | **Initrd** (zstd), enthält Stage-1-Module, Firmware-Ausschnitte, systemd-Initrd-Helfer |
| `loader/` | ~MB | systemd-boot + Einträge `.conf` |
| `EFI/systemd/` | klein | systemd-bootx64.efi |

Jeder **Menü-Eintrag** (Generation) ist eine **~4 KB** `.conf` mit `init=/nix/store/…-nixos-system-…/init` — zeigt auf **dieselben** EFI-Dateien solange Kernel-Version gleich.

Gepinnte Baseline Gen 85/86 (`boot-baseline.nix`): nur extra `.conf`, **kein** zweites Kernel-Paar.

---

## generationLimit vs. Kernel-Versionen {#generation-limit}

```nix
# profile.nix
boot.generationLimit = 15;  # = boot.loader.systemd-boot.configurationLimit
```

- **15 Generationen** → max. 15 sichtbare Boot-Einträge + ältere werden ausgeblendet
- **Kein** `15 × 50 MB` auf der ESP — das war eine vereinfachte Worst-Case-Rechnung für *Kernel-Kopien*
- Du kannst **15 Generationen** für Step-by-Step-Rollback behalten und trotzdem **512 MB** ESP

**ESP räumt alte Kernel-Paare auf** wenn nixpkgs die Version wechselt — nicht automatisch bei jedem `switch`.

---

## Optimierung — Low Hanging Fruit? {#optimierung}

### bzImage.efi (~14 MB) — **geringes Potenzial**

- Größe = komprimierter Kernel + EFI-Header; Treiber als **Module** sind schon ausgelagert (kernel-slim)
- `boot.kernelPackages = linuxPackages_latest` — Wechsel auf `linuxPackages` (_nicht_ latest) spart selten >1 MB
- **UKI** (Unified Kernel Image) — anderes Format, nicht kleiner per se; NixOS-Ökosystem noch optional

**Fazit:** Lohnender Audit-Aufwand gering. kernel-slim ist bereits der Hebel.

### initrd.efi (~33 MB) — **mittleres Potenzial** (heikel)

Größter Block. Initrd enthält u. a.:

- `boot.initrd.availableKernelModules` (SATA/USB: xhci_pci, ahci, usb_storage, sd_mod)
- `boot.initrd.kernelModules` — **i915** früh für KMS (`hardware.nix`)
- Firmware-Ausschnitte (`hardware.firmware = [ linux-firmware ]` in kernel-slim)
- systemd-basierter initrd (ADR-020 — bewusst, nicht zurück zu legacy)

**Mögliche Hebel (jeder braucht Test nach Rebuild):**

| Hebel | Ersparnis (grob) | Risiko |
|-------|------------------|--------|
| i915 erst nach Stage-1 (aus initrd entfernen) | ~2–5 MB | Kein früher Framebuffer, langsamerer Boot |
| Firmware nur modul-spezifisch statt linux-firmware-Bulk | ~5–15 MB | Fehlende FW für NIC/GPU im Initrd |
| Weniger initrd-Module (wenn HW bekannt stabil) | ~1–3 MB | Boot von USB-Install-Stick ggf. kaputt |
| `boot.initrd.compressor = "zstd"` (Default) | — | bereits aktiv |

**Empfehlung:** Erst **nach** stabiler 512M-ESP-Reinstall mit `lsinitrd`/`du` auf echtem `/boot` messen. Kein Blind-Optimieren auf kaputtem/unmounted ESP. Phase 2-Audit in ROADMAP, nicht vor Stufe-3-Install.

### systemd-boot / Loader — **kein Potenzial**

~1–2 MB, nicht sinnvoll anfassen.

---

## Siehe auch {#siehe-auch}

- [GUIDE-disko-learning.md](GUIDE-disko-learning.md) — disko ESP 512M
- [ADR-3024](../adr/3024-disko-tier-a-provisioning.md#esp-sizing)
- [ADR-020](../adr/020-no-legacy-explicit-stack.md) — systemd-boot vs. GRUB