---
meta:
  role: doc
  purpose: ADR-2027 Kernel-Slim — Modul-Blacklisting-Policy (Whitelist/Blacklist Zwiebelschale)
  status: accepted
  date: 2026-07-05
  error_pattern: "modprobe: FATAL: Module .* not found|modprobe: ERROR.*could not insert|module blacklisted"
  quick_fix: "lsmod | grep <modul>; journalctl -b | grep -i 'module.*black\\|modprobe.*error'"
  services: []
  betrifft:
    - lib/kernel/policy.nix
    - lib/kernel/blacklist-filesystems.nix
    - lib/kernel/blacklist-global.nix
    - lib/kernel/blacklist-homelab-headless.nix
    - lib/kernel/whitelist-homelab.nix
    - modules/20-security/25-kernel-policy.nix
    - machines/q958/kernel-slim.nix
  docs:
    - docs/adr/2026-kernel-hardening-sysctl.md
    - docs/guides/GUIDE-kernel-hardening.md
  tags:
    - adr
    - kernel
    - blacklist
    - security
    - module-policy
---

# ADR-2027: Kernel-Slim — Modul-Blacklisting-Policy {#adr-2027}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-05 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

---

## Kontext {#kontext}

- Kernel-Module, die via udev automatisch geladen werden, vergrößern die Angriffsfläche erheblich.
- Exotische Dateisystem-Parser laufen in Ring 0 (Kernel-Space) und sind bekannte Einfallstore für Privilege Escalation via präparierte Images oder USB-Sticks.
- Datacenter-, Enterprise-Storage- und Legacy-Bus-Treiber haben auf einem Homelab-Server keinerlei Verwendung, binden aber RAM und exponieren Angriffsfläche.
- NixOS-`boot.blacklistedKernelModules` genügt für einfache Fälle, aber ein Homelab mit mehreren Profilen (headless-server, desktop, blank für Tests) braucht eine strukturierte Policy.

## Entscheidung {#entscheidung}

**Dreischichtige Blacklist-Policy via `lib/kernel/policy.nix` — aktiv ab Rollout-Stufe 1 im Modus `homelab-strict`.**

### Schicht A — Globale Blacklist {#schicht-a}

Immer aktiv, profilunabhängig. Enthält:
- Exotische/Legacy Netzwerkprotokolle (`dccp`, `sctp`, `rds`, `tipc`, Amateurfunk)
- Datacenter-NICs und -Storage-Controller (keine Mellanox/InfiniBand im Homelab)
- Legacy-Bus-Hardware (Floppy, Parallelport, PCMCIA, IDE)
- Exotische Dateisysteme (Cluster-FS, Flash-FS, Legacy-UNIX-FS, macOS HFS/HFS+)

```nix
# lib/kernel/blacklist-filesystems.nix — exotische Dateisysteme {#libkernelblacklist-filesystemsnix-exotische-dateisysteme}
[ "gfs2" "ceph" "xfs" "btrfs" "f2fs" "jffs2" "erofs" "cramfs"
  "hfs" "hfsplus" "udf" "isofs" "minix" "sysv" ... ]
# exfat bewusst NICHT geblacklistet — USB-Sticks mit exFAT sind valid {#exfat-bewusst-nicht-geblacklistet-usb-sticks-mit-exfat-sind-valid}
```bash

### Schicht B — Homelab-Profil headless-server {#schicht-b}

Aktiv wenn `homelabProfile = "headless-server"`. Entfernt Audio, Webcam, Bluetooth, WiFi-Treiber — ein Server braucht diese nicht.

### Schicht C — Host-spezifische Blacklist {#schicht-c}

In `machines/q958/profile.nix` → `kernel.blacklist.*`. Ermöglicht host-spezifische Einschränkungen ohne gemeinsame Bibliothek zu verändern.

### Whitelist-Assertions {#whitelist-assertions}

Im Modus `homelab-strict` prüft die Policy bei jedem Build:
- Alle `requiredModules` sind explizit in `whitelist-homelab.nix` gelistet.
- Kein `requiredModule` landet auf der effektiven Blacklist.

```bash
# Assertion-Fehler im Build: {#assertion-fehler-im-build}
# KERNEL-POLICY: Pflichtmodul 'xyz' ist weder in der Homelab-Whitelist {#kernel-policy-pflichtmodul-xyz-ist-weder-in-der-homelab-whitelist}
# noch in kernel.whitelistExtra — Profil oder whitelistExtra anpassen. {#noch-in-kernelwhitelistextra-profil-oder-whitelistextra-anpassen}
```

### Modi {#modi}

| Modus | Schichten | Assertions |
|-------|-----------|------------|
| `blank` | Keine | Keine |
| `global-only` | A | Keine |
| `homelab-strict` | A + B + C | ✅ Whitelist-Pflicht |
| `homelab-relaxed` | A + B + C | Optional |

**q958 läuft: `homelab-strict` + `headless-server`.**

## Diagnose {#diagnose}

**Symptom:** Treiber/Modul fehlt, Service startet nicht.

```bash
# Geblacklisted? {#geblacklisted}
cat /etc/modprobe.d/blacklist.conf | grep <modul>

# Aktuell geladene Module {#aktuell-geladene-module}
lsmod | grep <modul>

# Kernel-Meldungen beim Boot {#kernel-meldungen-beim-boot}
journalctl -b | grep -iE "module.*black|modprobe.*error|could not insert"
```text

**Erwarteter Output bei Blacklist-Treffer:**
```
kernel: blacklisted <modul>
modprobe: ERROR: could not insert 'modul': Operation not permitted
```bash

## Fix {#fix}

```bash
# 1. Modul als requiredModule eintragen (machines/q958/profile.nix) {#1-modul-als-requiredmodule-eintragen-machinesq958profilenix}
# kernel.requiredModules = [ "mein_modul" ]; {#kernelrequiredmodules-mein_modul}

# 2. Oder in whitelistExtra (wenn nicht in whitelist-homelab.nix) {#2-oder-in-whitelistextra-wenn-nicht-in-whitelist-homelabnix}
# kernel.whitelistExtra = [ "mein_modul" ]; {#kernelwhitelistextra-mein_modul}

# 3. Dry-build (Assertions prüfen!) {#3-dry-build-assertions-pruefen}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# 4. Switch in tmux {#4-switch-in-tmux}
# tmux new-session 'sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure 2>&1 | tee /tmp/nixos-switch.log; read' {#tmux-new-session-sudo-nixos-rebuild-switch---flake-etcnixosq958---impure-21-tee-tmpnixos-switchlog-read}
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Dateisystem-Kernel-Parser für exotische Typen (HFS, cramfs, udf) können nicht via manipulierten USB-Stick oder Image getriggert werden.
- RAM-Einsparung: mehrere hundert KB durch nicht geladene Treiber (messbar via `lsmod`).
- Build-Zeit-Assertions verhindern Silent-Failures: Fehler sichtbar bei `nixos-rebuild`, nicht erst beim Boot.
- Whitelist-Dokumentation in `whitelist-homelab.nix` ist explizite Entscheidung über erlaubte Hardware.

### Negativ / Trade-offs {#negativ}

- exFAT USB-Sticks funktionieren (nach Entscheidung 2026-07-05 aus Blacklist entfernt).
- XFS, Btrfs, F2FS geblacklistet — wenn zukünftig ein Laufwerk mit diesen Dateisystemen angeschlossen wird, ist manuelles Whitelisting nötig.
- Neue Hardware (z. B. ein nicht gelisteter NIC) erfordert expliziten Eintrag in `requiredModules` + `whitelist-homelab.nix`.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Policy-Engine | `lib/kernel/policy.nix` |
| Globale Blacklist (Protokolle, DC, Legacy) | `lib/kernel/blacklist-global.nix` |
| Filesystem-Blacklist | `lib/kernel/blacklist-filesystems.nix` |
| Homelab-Headless-Blacklist (Audio/BT/WiFi) | `lib/kernel/blacklist-homelab-headless.nix` |
| Hardware-Whitelist | `lib/kernel/whitelist-homelab.nix` |
| NixOS-Option-Modul | `modules/20-security/25-kernel-policy.nix` |
| Host-Verdrahtung | `machines/q958/kernel-slim.nix` |

### Verifikation {#verifikation}

```bash
# Assertions wurden erfüllt (kein Build-Fehler) → Policy korrekt {#assertions-wurden-erfuellt-kein-build-fehler-policy-korrekt}
# Effektive Blacklist nach Boot {#effektive-blacklist-nach-boot}
cat /etc/modprobe.d/blacklist.conf | wc -l   # Viele Einträge = aktiv

# Kein exotisches FS ladbar (Test mit Dummy): {#kein-exotisches-fs-ladbar-test-mit-dummy}
sudo modprobe hfs 2>&1   # → FATAL: Module hfs not found / blacklisted
```text

## Alternativen verworfen {#alternativen}

- **`security.lockKernelModules` allein** — sperrt alle Module nach Boot, löst aber nicht das Problem von Modulen die *während* des Boots geladen werden. Komplementär, nicht alternativ ([ADR-2026](2026-kernel-hardening-sysctl.md#lockdown)).
- **Kein Blacklisting** — mehr Angriffsfläche, kein RAM-Gewinn. Abgelehnt.
- **Whitelist-only (alle anderen blockiert)** — in NixOS ohne Custom-Kernel-Build nicht praktikabel; Blacklist ist der machbare Kompromiss.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-05 | Initial; exfat aus Blacklist entfernt (USB-Stick-Support) |

## Siehe auch {#siehe-auch}

- [ADR-2026 — Kernel-Härtung sysctl](2026-kernel-hardening-sysctl.md) — komplementäre Kernel-Härtungsschicht
- [ADR-028 — Systemd Service Isolation](028-systemd-service-isolation.md) — Sandbox auf Anwendungsebene
- [GUIDE-kernel-hardening.md](../guides/GUIDE-kernel-hardening.md) — Betriebsguide
