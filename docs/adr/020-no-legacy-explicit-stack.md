---
meta:
  role: doc
  purpose: Explizit ersetzte Technologien — was und warum nicht mehr im Stack ist
  status: accepted
  date: 2026-06-30
  tags:
    - governance
    - policy
    - boot
    - systemd
    - kernel
    - no-legacy
  docs:
    - docs/adr/README.md
    - docs/adr/008-nftables-l4-hardening.md
    - docs/adr/011-unified-port-uid-schema.md
---

# ADR-020: Explizit ersetzte Technologien (No-Legacy Policy)

**Status:** Accepted  
**Datum:** 2026-06-30  
**Kontext:** Wissenssicherung aus mynixos (erstes Repo, 2026) — dort als `90-policy/no-legacy.nix` explizit durchgesetzt

---

## Problem

Implizite Entscheidungen verrottten: In drei Jahren weiß niemand mehr warum GRUB weg ist, warum es keinen Cron-Daemon gibt, warum NetworkManager nie installiert war. Dieses ADR macht die Entscheidungen explizit und dauerhaft.

---

## Entscheidungsmatrix: Was wurde ersetzt und warum

### Boot

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| GRUB | `systemd-boot` | Einfacher, wartungsärmer, EFI-nativ, kein 2-Stage-Bootloader-Overhead; `configurationLimit = 5` verhindert ESP-Überlauf |
| Legacy initrd | systemd-basierter initrd | Schnellere Boot-Sequenz, bessere Fehlerdiagnose über journald |

**NixOS-Konfiguration:**
```nix
boot.loader.systemd-boot.enable = true;
boot.loader.systemd-boot.configurationLimit = 5;  # ESP-Schutz
```

---

### Netzwerk

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| NetworkManager | `systemd-networkd` | Deterministisch, declarativ, kein GUI-Overhead, besser für Server |
| ifupdown | systemd-networkd | Veraltet, nicht mehr gepflegt |
| iptables | `nftables` | Modernes Firewall-Framework, bessere Performance, atomic rule updates → ADR-008 |
| Legacy SMB (< SMB2.1) | Nicht genutzt | Sicherheitslücken, keine modernen Clients benötigen das |

---

### Task-Scheduling

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| `cron` / `crond` | `systemd.timers` | Integriert in journald-Logging, Dependency-Management, `OnCalendar` ist flexibler; cron hat kein Logging by default |
| `anacron` | `systemd.timers` mit `Persistent = true` | `Persistent = true` macht dasselbe wie anacron (verpasste Timer nachholen) |

**Beispiel:**
```nix
systemd.timers.my-job = {
  timerConfig = {
    OnCalendar = "*-*-* 03:00:00";
    Persistent = true;  # anacron-äquivalent
  };
};
```

---

### Dateisysteme

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| ext2, ext3 | ext4 | ext2/3 sind veraltet, kein Journal (ext2) oder langsam (ext3) |
| jfs, reiserfs | ext4 | Reiserfs tot (maintainer im Gefängnis), JFS niche |
| HFS/HFS+ | Nicht relevant | Nur macOS-spezifisch, kein Anwendungsfall |
| Swap-Partition | `zram-generator` | RAM-Kompression via ZRAM ist schneller als Disk-Swap; sysctl `vm.swappiness = 180` für ZRAM-Präferenz |

---

### Monitoring & Logging

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| Prometheus | VictoriaMetrics | Leichter, kompatible PromQL-API, weniger RAM → chat_insights #38 |
| Rsyslog / syslog-ng | journald + Vector | journald ist systemd-nativ, Vector gibt strukturierten Push zu Loki |
| Netdata | Grafana + VictoriaMetrics | Weniger moving parts, keine Cloud-Abhängigkeit |

---

### DNS

| Abgelöst | Ersatz | Grund |
|----------|--------|-------|
| Blocky | Technitium DNS | Blocky hat DNS-over-TLS (DoT) fail-open-Verhalten gezeigt → ADR-001; Technitium hat vollständigere DoT-Implementierung |
| systemd-resolved (als Stub) | Technitium lokal | Vollständige DNS-Kontrolle, kein doppeltes Stub-Layer |

---

### Kernel-Module (blacklisted)

Für headless q958 ohne WiFi/Bluetooth/GPU gibt es keine Rechtfertigung für diese Module im Kernel:

```nix
# kernel-slim.nix (machines/q958/)
boot.blacklistedKernelModules = [
  # WiFi — nicht vorhanden auf q958
  "iwlwifi" "ath9k" "rtl8192cu"
  # Bluetooth — kein Anwendungsfall
  "bluetooth" "btusb" "btrtl"
  # GPU-Treiber — headless, keine GUI
  "nouveau" "radeon" "amdgpu"
  # Legacy-Hardware
  "pcspkr" "iTCO_wdt"
];
```

**Prinzip:** Nicht installierter Code = keine Angriffsfläche. Security-by-reduction.

---

## Was NICHT ersetzt wurde (bewusste Entscheidungen)

| Technologie | Begründung für Beibehaltung |
|-------------|----------------------------|
| SSH | Standard-Protokoll, keine sinnvolle Alternative für Remote-Access |
| ext4 | Bewährtes Dateisystem für persistente Partitionen; kein Btrfs (overhead) oder ZFS (Lizenz) |
| PostgreSQL | Relational DB als Fundament; SQLite nur für Dienst-interne State (Vaultwarden etc.) |

---

## Assertions (Build-Time-Enforcement)

Nix-Grok erzwingt folgende Policies zur Build-Zeit:

| Code | Assertion | Fundstelle |
|------|-----------|------------|
| [SEC-TIER-C] | Kein Dienst darf HDD (Tier-C) schreiben ohne Exemption | `modules/30-storage/05-storage-policy.nix` |
| [SEC-NET-001] | Firewall muss aktiv sein | Implizit via `networking.firewall.enable = true` in 01-core.nix |
| [PORT-REGISTRY] | Keine doppelten Ports in my.ports | `lib/services-spec.nix` |
| [SERVICES-SPEC] | Keine doppelten Ports in services-spec | `lib/services-spec.nix` |

**Empfehlung ausstehend:** Systematische Security-Assertions mit Codes (wie im alten mynixos) sind ein offener Punkt — siehe Abschnitt "Offene Punkte".

---

## Offene Punkte (nicht implementiert, aber bekannt)

1. **Security-sysctl fehlen**: Das alte mynixos hatte `kernel.kptr_restrict`, `net.ipv4.conf.all.rp_filter` etc. Nix-Grok hat nur Performance-sysctl. → Zukünftiger ADR.
2. **/boot-Monitoring**: Script für >85% ESP-Auslastungswarnung. `configurationLimit = 5` ist Prävention, kein Monitoring.
3. **Binary-Only als explizite Policy**: Das alte mynixos hatte `nix.settings.max-jobs = 0` als Policy-Entscheidung. Nix-Grok verwendet RAM-basiertes max-jobs (erlaubt begrenzte lokale Builds). Das ist pragmatischer aber weniger strikt.

---

## Verwandte ADRs

- ADR-001: DNS-over-TLS (Technitium statt Blocky)
- ADR-002: IPv4-only Homelab
- ADR-008: nftables L4 Hardening
- ADR-012: Modern CLI Tools
- ADR-019: UDS-First Philosophy
