---
meta:
  role: doc
  purpose: Betriebsguide Kernel-Härtung — Kernel-Slim, sysctl, Systemd Service Isolation
  date: 2026-07-10
  status: current
  docs:
    - docs/adr/2026-kernel-hardening-sysctl.md
    - docs/adr/2027-kernel-slim-module-policy.md
    - docs/adr/028-systemd-service-isolation.md
    - modules/20-security/2026-kernel-hardening.nix
    - modules/20-security/2027-hardened-core.nix
    - lib/kernel/policy.nix
    - lib/systemd-hardening.nix
  tags:
    - security
    - kernel
    - hardening
    - systemd
---

# Guide: Kernel-Härtung {#guide-kernel-hardening}

> Drei Sicherheitsschichten: Kernel-Slim (Modul-Blacklisting) · sysctl + Boot-Parameter · Systemd Service Isolation.  
> Aktivierung: Schichten 1–2 ab Rollout-Stufe 8, Lockdown (Stufe 3) ab Stufe 9.

## Schichtenmodell {#schichten}

```text
┌─────────────────────────────────────────────┐
│  Schicht 3: Systemd Service Isolation       │  ← mkHardened, ProtectHome, DynamicUser
│  (Anwendungsebene, per Dienst)              │
├─────────────────────────────────────────────┤
│  Schicht 2: Kernel sysctl + Boot-Parameter  │  ← 26-kernel-hardening.nix (Stufe 8)
│  (System-Ebene, global)                     │
├─────────────────────────────────────────────┤
│  Schicht 1: Kernel-Slim (Modul-Blacklist)   │  ← lib/kernel/, 25-kernel-policy.nix (Stufe 1)
│  (Boot-Zeit, verkleinert Angriffsfläche)    │
└─────────────────────────────────────────────┘
```

## Schicht 1 — Kernel-Slim: Modul-Blacklisting {#kernel-slim}

**Entscheidung:** [ADR-2027](../adr/2027-kernel-slim-module-policy.md)

### Was wird geblacklistet? {#was-geblacklistet}

| Gruppe | Beispiele | Grund |
|--------|-----------|-------|
| Exotische Dateisysteme | `hfs`, `hfsplus`, `cramfs`, `jffs2`, `udf` | Ring-0-Parser, Privilege-Escalation-Einfallstor |
| Cluster-Dateisysteme | `gfs2`, `ceph` | Kein SAN/Ceph im Homelab |
| Häufige Linux-Alternativen | `xfs`, `btrfs`, `f2fs` | Nicht in Nutzung (ext4 + ZFS) |
| Datacenter-NICs | `mlx5_core`, `i40e`, `ice` | Kein Datacenter-Equipment |
| Legacy-Bus | `floppy`, `parport`, `firewire-ohci` | Obsolete Hardware |
| Netzwerkprotokolle | `dccp`, `sctp`, `rds`, `tipc` | Angriffsfläche ohne Verwendung |

**exFAT ist bewusst NICHT geblacklistet** — USB-Sticks mit exFAT funktionieren (Entscheidung 2026-07-05).

### Modus q958 {#modus-q958}

```nix
# machines/q958/kernel-slim.nix {#machinesq958kernel-slimnix}
my.core.kernel-slim = {
  mode = "homelab-strict";      # Whitelist-Assertions aktiv
  homelabProfile = "headless-server";   # Audio/BT/WiFi auch geblacklistet
};
```bash

### Neues Modul hinzufügen {#neues-modul}

```nix
# machines/q958/profile.nix → kernel.requiredModules {#machinesq958profilenix-kernelrequiredmodules}
kernel.requiredModules = [ "mein_treiber" ];
# UND falls nicht in whitelist-homelab.nix: {#und-falls-nicht-in-whitelist-homelabnix}
kernel.whitelistExtra = [ "mein_treiber" ];
```

```bash
# Assertions prüfen beim Dry-build: {#assertions-pruefen-beim-dry-build}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
# Fehler: "KERNEL-POLICY: Pflichtmodul 'xyz' ist weder in der Homelab-Whitelist..." {#fehler-kernel-policy-pflichtmodul-xyz-ist-weder-in-der-homelab-whitelist}
```bash

### Verifikation {#kernel-slim-verifikation}

```bash
# Effektive Blacklist {#effektive-blacklist}
cat /etc/modprobe.d/blacklist.conf | wc -l

# Modul testen (sollte fehlschlagen) {#modul-testen-sollte-fehlschlagen}
sudo modprobe hfs 2>&1   # → FATAL: Module hfs not found / blacklisted
sudo modprobe cramfs 2>&1

# Aktuell geladene Module (muss kurz sein!) {#aktuell-geladene-module-muss-kurz-sein}
lsmod | wc -l
```

---

## Schicht 2 — Kernel sysctl + Boot-Parameter {#kernel-sysctl}

**Entscheidung:** [ADR-2026](../adr/2026-kernel-hardening-sysctl.md) · Aktiv ab Stufe 8

### Wichtigste sysctl-Werte {#sysctl-werte}

```bash
# Kernel-Introspektion blockiert {#kernel-introspektion-blockiert}
kernel.dmesg_restrict = 1         # Nur root liest dmesg
kernel.kptr_restrict = 2          # Kernel-Pointer nie sichtbar
kernel.unprivileged_bpf_disabled = 1  # Kein eBPF ohne CAP_BPF
vm.mmap_rnd_bits = 32             # Max. ASLR-Entropie

# Ptrace eingeschränkt (bewusst auf 1, nicht 2) {#ptrace-eingeschraenkt-bewusst-auf-1-nicht-2}
kernel.yama.ptrace_scope = 1      # Nur Parent-Child-Beziehungen

# Netzwerk-Härtung {#netzwerk-haertung}
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.core.bpf_jit_harden = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
```text

### Boot-Parameter {#boot-parameter}

| Parameter | Wirkung |
|-----------|---------|
| `slab_nomerge` | Verhindert SLAB-Merging (Exploit-Technik) |
| `init_on_alloc=1` | Speicher bei Alloc null-initialisiert |
| `init_on_free=1` | Heap-Spray-Schutz |
| `vsyscall=none` | Legacy vsyscall deaktiviert (ROP-Gadget) |
| `randomize_kstack_offset=on` | Stack-Offset per Syscall randomisiert |
| `intel_iommu=on` | DMA-Angriffe via IOMMU blockiert |
| `kfence.sample_interval=100` | 1 % UAF/OOB-Sampling |

### Mount-Flags {#mount-flags}

```bash
findmnt /tmp      # → noexec,nosuid,nodev
findmnt /dev/shm  # → noexec,nosuid,nodev,size=50%
findmnt /run/lock # → noexec,nosuid,nodev
```

### Kernel-Lockdown (Stufe 9) {#lockdown}

```bash
# Status prüfen {#status-pruefen}
cat /sys/kernel/security/lockdown
# Erwartet (Stufe 9): confidentiality {#erwartet-stufe-9-confidentiality}
cat /proc/sys/kernel/modules_disabled
# Erwartet (Stufe 9): 1 {#erwartet-stufe-9-1}
```text

> **Nach Stufe-9-Aktivierung kein Treiber-Hotplug mehr.** Neue Hardware → Reboot nötig.

### Verifikation {#sysctl-verifikation}

```bash
sysctl kernel.unprivileged_bpf_disabled   # → 1
sysctl kernel.yama.ptrace_scope           # → 1
sysctl vm.mmap_rnd_bits                   # → 32
sysctl kernel.dmesg_restrict              # → 1
# Kurzcheck aller Härtungs-Parameter: {#kurzcheck-aller-haertungs-parameter}
sysctl -a 2>/dev/null | grep -E "bpf_disabled|kptr_restrict|dmesg_restrict|ptrace_scope"
```

---

## Schicht 3 — Systemd Service Isolation {#systemd-isolation}

**Entscheidung:** [ADR-028](../adr/028-systemd-service-isolation.md)

### mkHardened Factory {#mkhardened}

```nix
# lib/systemd-hardening.nix importieren {#libsystemd-hardeningnix-importieren}
{ lib, hardening, ... }:
systemd.services.mein-dienst.serviceConfig = lib.mkMerge [
  (hardening.mkHardened {
    rw   = [ "/var/lib/mein-dienst" ];   # Schreib-Ausnahmen
    caps = [];                           # Keine extra Capabilities
    mdwx = true;                         # MemoryDenyWriteExecute (default)
  })
  { DynamicUser = true; ExecStart = "..."; }
];
```text

### Härtungsflags im Überblick {#hardening-flags}

| Flag | Wirkung |
|------|---------|
| `ProtectSystem = "strict"` | Dateisystem read-only (außer `ReadWritePaths`) |
| `ProtectHome = true` | `/home` komplett ausgeblendet |
| `PrivateTmp = true` | Eigenes `/tmp` pro Dienst |
| `PrivateDevices = true` | Kein `/dev`-Zugriff |
| `NoNewPrivileges = true` | Kein Privilege-Escalation via setuid |
| `MemoryDenyWriteExecute = true` | Kein JIT/Shellcode |
| `DynamicUser = true` | Flüchtiger User ohne Shell und Heimverzeichnis |

### Ausnahmen {#ausnahmen}

```nix
# Jellyfin: Hardware-Transcoding braucht /dev/dri {#jellyfin-hardware-transcoding-braucht-devdri}
serviceConfig = mkHardened {
  mdwx = false;   # .NET JIT braucht W+X-Speicher
} // {
  PrivateDevices = false;   # Kein DevicePolicy=closed
  SupplementaryGroups = [ "render" "video" ];
};
```

### Dienst-Hardening prüfen {#dienst-check}

```bash
# Alle Flags eines Dienstes anzeigen {#alle-flags-eines-dienstes-anzeigen}
systemctl show jellyfin | grep -E 'ProtectSystem|ProtectHome|NoNew|DynamicUser|MemoryDeny|PrivateTmp'

# systemd-analyze security gibt Score {#systemd-analyze-security-gibt-score}
systemd-analyze security jellyfin   # Ziel: Score < 5 (grün)
```text

**Erwartete Ausgabe für gehärteten Dienst:**
```
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
PrivateTmp=yes
```yaml

---

## Häufige Probleme {#probleme}

### Dienst schreibt nicht in sein Datenverzeichnis {#schreibfehler}

```bash
journalctl -u mein-dienst | grep -i "read-only\|permission denied"
# Fix: ReadWritePaths = [ "/var/lib/mein-dienst" ]; in serviceConfig {#fix-readwritepaths-varlibmein-dienst-in-serviceconfig}
```

### Hardware-Gerät nicht gefunden {#hardware-fehler}

```bash
# PrivateDevices=true blendet /dev aus {#privatedevicestrue-blendet-dev-aus}
# Fix: {#fix}
serviceConfig.PrivateDevices = false;
serviceConfig.DeviceAllow = [ "/dev/dri rw" ];
serviceConfig.SupplementaryGroups = [ "render" "video" ];
```bash

### Modul fehlt nach Kernel-Slim {#modul-fehlt}

```bash
# Modul zur requiredModules-Liste in profile.nix hinzufügen {#modul-zur-requiredmodules-liste-in-profilenix-hinzufuegen}
kernel.requiredModules = [ "fehlendes_modul" ];
# + ggf. in whitelistExtra wenn nicht in whitelist-homelab.nix {#ggf-in-whitelistextra-wenn-nicht-in-whitelist-homelabnix}
```

---

## Siehe auch {#siehe-auch}

- [ADR-2026 — Kernel-Härtung sysctl](../adr/2026-kernel-hardening-sysctl.md)
- [ADR-2027 — Kernel-Slim Modul-Policy](../adr/2027-kernel-slim-module-policy.md)
- [ADR-028 — Systemd Service Isolation](../adr/028-systemd-service-isolation.md)
- [ADR-2029 — mTLS Zero-Trust (proposed)](../adr/2029-mtls-zero-trust-internal.md)
- [GUIDE-security-secrets.md](GUIDE-security-secrets.md) — SSH, Sovereign Unlock, Secrets
- [GUIDE-nftables-hardening.md](GUIDE-nftables-hardening.md) — Netzwerk-Härtung (Schicht 4)
