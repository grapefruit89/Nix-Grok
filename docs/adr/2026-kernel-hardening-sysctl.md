---
meta:
  role: doc
  purpose: ADR-2026 Kernel-Härtung — sysctl, Boot-Parameter, Mount-Flags
  status: accepted
  date: 2026-07-05
  error_pattern: "ERROR: could not insert module|Operation not permitted.*lockdown|Lockdown: direct memory|kernel.* write protected"
  quick_fix: "journalctl -b | grep -iE 'lockdown|module.*denied|sysctl.*fail'"
  services: []
  betrifft:
    - modules/20-security/2026-kernel-hardening.nix
    - modules/20-security/2027-hardened-core.nix
    - machines/q958/rollout.nix
  docs:
    - docs/adr/2027-kernel-slim-module-policy.md
    - docs/adr/028-systemd-service-isolation.md
    - docs/adr/2008-nftables-l4-hardening.md
    - docs/guides/GUIDE-kernel-hardening.md
  tags:
    - adr
    - kernel
    - sysctl
    - security
    - hardening
---

# ADR-2026: Kernel-Härtung — sysctl, Boot-Parameter, Mount-Flags {#adr-2026}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-05 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

---

## Kontext {#kontext}

- Ein kompromittierter Dienst oder ein Zero-Day-Exploit kann trotz eingeschränkter Rechte tiefe Kernel-Strukturen manipulieren, wenn Kernel-seitige Härtung fehlt.
- Standardmäßige NixOS-Kernel-Parameter sind auf maximale Kompatibilität ausgelegt, nicht auf minimale Angriffsfläche.
- eBPF-Rootkits, DMESG-Leakage, Speichermanipulation via Ptrace und unsichere Mount-Points (`/tmp`, `/dev/shm`) sind bekannte Einfallstore.
- `26-kernel-hardening.nix` und `27-hardened-core.nix` implementieren diese Schicht; Aktivierung via Rollout-Stufe 8 (`kernel-hardening`) bzw. Stufe 9 (`hardened`).

## Entscheidung {#entscheidung}

**Mehrschichtige Kernel-Härtung via sysctl, Boot-Parameter und Mount-Flags — aktiv ab Rollout-Stufe 8.**

### sysctl — Speicher und Introspektion {#sysctl-memory}

```nix
# modules/20-security/2026-kernel-hardening.nix {#modules20-security26-kernel-hardeningnix}
boot.kernel.sysctl = {
  "kernel.dmesg_restrict"        = 1;   # Nur root liest dmesg
  "kernel.kptr_restrict"         = 2;   # Kernel-Pointer nie an Userspace
  "kernel.yama.ptrace_scope"     = 1;   # Nur Parent-Prozesse dürfen ptrace
  "kernel.sysrq"                 = 0;   # SysRq komplett deaktiviert
  "kernel.unprivileged_bpf_disabled" = 1;  # Kein eBPF ohne CAP_BPF
  "vm.unprivileged_userfaultfd"  = 0;
  "vm.mmap_rnd_bits"             = 32;  # Max. ASLR-Entropie
  "kernel.core_pattern"          = "|/bin/false";  # Core dumps verworfen
};
```text

> **ptrace_scope = 1 (bewusste Entscheidung):** Der Wert `2` würde GDB und Debugger für normale User-Sessions brechen. Wert `1` begrenzt Ptrace auf Parent-Child-Beziehungen — ausreichend für ein Homelab ohne unprivilegierte Angreifer.

### sysctl — Netzwerk {#sysctl-network}

```nix
"net.core.bpf_jit_harden"              = 2;
"net.ipv4.conf.all.accept_source_route" = 0;
"net.ipv4.conf.all.accept_redirects"    = 0;
"net.ipv4.conf.all.log_martians"        = 1;
"net.ipv4.conf.all.rp_filter"           = 1;
"net.ipv4.tcp_syncookies"               = 1;
"net.ipv4.icmp_echo_ignore_all"         = 1;
"net.ipv4.tcp_timestamps"               = 0;
"fs.protected_hardlinks"                = 1;
"fs.protected_symlinks"                 = 1;
"fs.protected_regular"                  = 2;
"fs.protected_fifos"                    = 2;
```

### Boot-Parameter {#boot-parameter}

```nix
boot.kernelParams = [
  "slab_nomerge"          # Verhindert SLAB-Merging (Exploit-Technik)
  "init_on_alloc=1"       # Null-initialisierter Speicher bei Alloc
  "init_on_free=1"        # Null-Überschreiben bei Free (Heap-Spray-Schutz)
  "mitigations=auto"      # Spectre/Meltdown auto-gepatcht
  "vsyscall=none"         # Legacy vsyscall deaktiviert (ROP-Gadget-Quelle)
  "page_alloc.shuffle=1"  # Randomisierte Free-Page-Reihenfolge
  "randomize_kstack_offset=on"  # Stack-Offset per Syscall randomisiert
  "kfence.sample_interval=100"  # KFENCE: 1 % UAF/OOB-Sampling
  "intel_iommu=on"        # DMA-Angriffe via IOMMU blockieren
];
# Production (Stufe 9) zusätzlich: {#production-stufe-9-zusaetzlich}
# "page_poison=1"   "debugfs=off"   (via my.mode == "production") {#page_poison1-debugfsoff-via-mymode-production}
```bash

### Mount-Härtung {#mount-haertung}

```nix
fileSystems."/tmp"     = { options = [ "noexec" "nosuid" "nodev" ]; };
fileSystems."/dev/shm" = { options = [ "noexec" "nosuid" "nodev" "size=50%" ]; };
fileSystems."/run/lock" = { options = [ "noexec" "nosuid" "nodev" ]; };
```

### Kernel-Lockdown (Stufe 9) {#lockdown}

```nix
# modules/20-security/2027-hardened-core.nix — aktiv wenn hardened.enable = true {#modules20-security27-hardened-corenix-aktiv-wenn-hardenedenable-true}
security.lockKernelModules = true;   # modules_disabled=1 nach dem Boot
boot.kernelParams = [ "lockdown=confidentiality" ];
```bash

`lockKernelModules` verhindert nach dem Boot jegliches Nachladen von Kernel-Modulen. Standard ist `true` ab `hardened.enable` (Stufe 9). Kein Treiber-Hotplug mehr im Production-Betrieb — bewusste Einschränkung.

## Diagnose {#diagnose}

**Symptom:** Modul lässt sich nicht laden, oder Dienst schlägt mit Lockdown-Fehler fehl.

```bash
journalctl -b | grep -iE "lockdown|module.*denied|could not insert"
sysctl kernel.unprivileged_bpf_disabled   # Sollte: 1
sysctl kernel.yama.ptrace_scope           # Sollte: 1
sysctl vm.mmap_rnd_bits                   # Sollte: 32
```

<details>
<summary>Vollständige Verifikation (ausklappen)</summary>

```bash
# Alle Härtungs-sysctl-Werte prüfen {#alle-haertungs-sysctl-werte-pruefen}
sysctl kernel.dmesg_restrict kernel.kptr_restrict kernel.sysrq \
       kernel.unprivileged_bpf_disabled vm.mmap_rnd_bits \
       net.core.bpf_jit_harden

# Mount-Flags prüfen {#mount-flags-pruefen}
findmnt /tmp /dev/shm /run/lock | grep -E "noexec|nosuid|nodev"

# Lockdown-Status (Production) {#lockdown-status-production}
cat /sys/kernel/security/lockdown
```bash

</details>

## Fix {#fix}

```bash
# 1. Dry-build nach Änderungen an kernel-hardening.nix {#1-dry-build-nach-aenderungen-an-kernel-hardeningnix}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# 2. Switch in tmux {#2-switch-in-tmux}
# tmux new-session 'sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure 2>&1 | tee /tmp/nixos-switch.log; read' {#tmux-new-session-sudo-nixos-rebuild-switch---flake-etcnixosq958---impure-21-tee-tmpnixos-switchlog-read}

# 3. Nach Reboot prüfen {#3-nach-reboot-pruefen}
sysctl kernel.unprivileged_bpf_disabled   # → 1
cat /proc/sys/kernel/modules_disabled     # → 1 (nur Stufe 9)
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- eBPF-Rootkits benötigen `CAP_BPF` — für unprivilegierte Prozesse nicht erlangbar.
- Kernel-Pointer sind nie im Userspace sichtbar (kein KASLR-Bypass via dmesg).
- Heap-Spray-Angriffe erschwert durch `init_on_alloc/free`.
- DMA-basierte Hardware-Angriffe via IOMMU blockiert.
- `/tmp`-Exploits (Shellcode-Injektion) durch `noexec` unmöglich.

### Negativ / Trade-offs {#negativ}

- `lockKernelModules` (Stufe 9) blockiert Treiber-Hotplug vollständig — Reboot nötig für neue Hardware.
- `init_on_alloc/free` kostet ~3–5 % CPU-Performance bei speicherintensiven Workloads.
- `icmp_echo_ignore_all = 1` macht den Host für Ping unsichtbar — nützlich, aber `gatus` braucht andere Health-Check-Methoden.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| sysctl + Mount + Boot-Params | `modules/20-security/2026-kernel-hardening.nix` |
| lockKernelModules + Dienst-Slimming | `modules/20-security/2027-hardened-core.nix` |
| Rollout-Aktivierung | `machines/q958/rollout.nix` (`erstAb 8`, `erstAb 9`) |

### Verifikation {#verifikation}

```bash
sysctl kernel.unprivileged_bpf_disabled   # → 1
sysctl vm.mmap_rnd_bits                   # → 32
findmnt /tmp | grep noexec                # Mount-Flag gesetzt
# Stufe 9: {#stufe-9}
cat /sys/kernel/security/lockdown         # → confidentiality
```text

## Alternativen verworfen {#alternativen}

- **`ptrace_scope = 2`** — bricht GDB und lokale Debug-Sessions. Wert `1` ist ausreichend für Homelab-Szenario. Abgelehnt.
- **`security.nixos.kernel.kernelHardened` (NixOS-Preset)** — aggressiver als nötig, deaktiviert z. B. `/proc/kcore` und bricht einige Monitoring-Tools. Eigene selektive Liste gewählt.
- **Kein lockKernelModules** — lässt die Hintertür für Modul-Injection nach Boot offen. Ab Stufe 9 aktiv.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-05 | Initial (aus Grok-Systemanalyse destilliert) |

## Siehe auch {#siehe-auch}

- [ADR-2027 — Kernel-Slim Modul-Blacklisting](2027-kernel-slim-module-policy.md) — welche Module gar nicht erst geladen werden
- [ADR-028 — Systemd Service Isolation](028-systemd-service-isolation.md) — Sandbox auf Anwendungsebene
- [ADR-2008 — nftables L4-Härtung](2008-nftables-l4-hardening.md) — Netzwerk-Härtung als komplementäre Schicht
- [GUIDE-kernel-hardening.md](../guides/GUIDE-kernel-hardening.md) — Betriebsguide mit Diagnose-Checklisten
