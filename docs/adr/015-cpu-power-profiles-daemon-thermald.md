---
meta:
  role: doc
  purpose: CPU-Energieverwaltung — power-profiles-daemon + thermald für Intel HWP/EPP auf Q958
  status: accepted
  date: 2026-06-29
  error_pattern: "thermald.*error|power-profiles-daemon.*failed|cpufreq.*error|EPP.*failed"
  quick_fix: "systemctl restart thermald power-profiles-daemon; powerprofilesctl get"
  services: [thermald, power-profiles-daemon]
  betrifft:
    - machines/q958/default.nix
  docs:
    - docs/adr/README.md
  tags:
    - adr
    - power
    - cpu
    - homelab
    - intel-pstate
    - thermald
---

# ADR 015 — CPU-Energieverwaltung: power-profiles-daemon + thermald {#adr-015}

## Status {#status}

`accepted` — live auf q958 nach Dry-Build 2026-06-29

## Kontext {#kontext}

Der Q958 nutzt `intel_pstate` im **active mode** (Hardware-Managed P-states / HWP):

```
scaling_driver:                     intel_pstate (active)
scaling_available_governors:        performance powersave
energy_performance_available_preferences: default performance balance_performance balance_power power
```

Mit `intel_pstate` in active mode steuert die CPU-Hardware ihre eigenen P-states via **HWP**. Software-Governors wie `schedutil` sind **nicht verfügbar**. Der richtige Hebel ist die **EPP (Energy Performance Preference)**.

Das System lief mit EPP-Standard (`default`/`balance_power`) — für einen Server mit sporadischen QuickSync-Transcoding-Bursts nicht optimal.

## Entscheidung {#entscheidung}

### `services.power-profiles-daemon.enable = true` {#ppd}

`power-profiles-daemon` (PPD) ist der moderne D-Bus-Dienst für Intel-Energieprofilverwaltung:
- Setzt EPP auf `balance_performance` wenn Profil = `balanced` (Default auf AC-Stromversorgung)
- Integriert korrekt mit `intel_pstate` + HWP
- Kein Konflikt mit `thermald`

### `services.thermald.enable = true` {#thermald}

Intel Thermal Management Daemon:
- Koordiniert CPU-Drosselung **bevor** kritische Temperaturen erreicht werden
- Nutzt DPTF-Tabellen adaptiv (ohne `configFile`)
- Kompatibel mit PPD: thermald agiert auf Wärme-Ebene, PPD auf Leistungs-Ebene

## Diagnose {#diagnose}

**Symptom:** QuickSync-Transcoding langsam, oder CPU throttelt unerwartet.

```bash
# Aktuellen EPP prüfen
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
# Soll: balance_performance

# PPD-Profil prüfen
powerprofilesctl get
# Soll: balanced

# Thermald-Status
systemctl status thermald --no-pager
journalctl -u thermald -n 20 --no-pager | grep -iE "error|warn|throttl"

# PPD-Status
systemctl status power-profiles-daemon --no-pager
```

## Fix {#fix}

```bash
# Dienste neu starten
sudo systemctl restart thermald power-profiles-daemon

# EPP manuell prüfen (nach restart)
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference

# Falls PPD nicht läuft: prüfen ob Konflikt mit anderem Governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
# Muss: intel_pstate (active)
```

## Konsequenzen {#konsequenzen}

- **Positiv:** EPP `balance_performance` — bessere QuickSync-Reaktion bei Transkodierung
- **Positiv:** Korrekte Integration in NixOS/Linux Intel-Energie-Stack
- **Positiv:** thermald verhindert thermisches Throttling proaktiv
- **Neutral:** PPD-Profil `balanced` ist Standard auf AC — keine manuelle Konfiguration nötig
- **Kein Breaking Change:** Bestehende Services nicht betroffen

## Verifikation {#verifikation}

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference  # balance_performance
powerprofilesctl get                                                      # balanced
systemctl status thermald                                                  # active (running)
```

## Alternativen verworfen {#alternativen}

- **`powerManagement.cpuFreqGovernor = "schedutil"`** — `schedutil` setzt `acpi-cpufreq` voraus; mit `intel_pstate` in active mode nicht in `scaling_available_governors`. Würde bei Systemstart scheitern. **Falsch für dieses System.** Abgelehnt.
- **TLP** — überschneidet sich mit PPD, kann Konflikte verursachen. Für Server (kein Akku) kein Mehrwert. Nicht eingesetzt.

## Siehe auch {#siehe-auch}

- [RUNBOOK — Diagnosebefehle](../RUNBOOK.md#diagnose) — allgemeine Service-Diagnose
