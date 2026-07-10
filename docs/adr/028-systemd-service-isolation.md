---
meta:
  role: doc
  purpose: ADR-028 Systemd Service Isolation — mkHardened Factory + DynamicUser
  status: accepted
  date: 2026-07-05
  error_pattern: "Permission denied|Read-only file system|Operation not permitted|ProtectSystem.*strict|NoNewPrivileges"
  quick_fix: "systemctl show <service> | grep -E 'ProtectSystem|ProtectHome|NoNew|DynamicUser|PrivateTmp'"
  services: []
  betrifft:
    - lib/systemd-hardening.nix
    - modules/60-apps/
    - modules/50-media/
  docs:
    - docs/adr/2026-kernel-hardening-sysctl.md
    - docs/adr/003-oom-cgroup-isolation.md
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/guides/GUIDE-kernel-hardening.md
  tags:
    - adr
    - systemd
    - hardening
    - isolation
    - security
---

# ADR-028: Systemd Service Isolation — mkHardened Factory {#adr-028}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-05 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

---

## Kontext {#kontext}

- Ein kompromittierter Dienst (z. B. eine Web-App oder KI-Agent) darf nicht auf globale SSH-Keys, Browser-Sessions, Tokens anderer Dienste oder das Home-Verzeichnis zugreifen können.
- NixOS-Module für Drittanbieter-Dienste (Jellyfin, Sonarr, etc.) setzen oft keine oder minimale Systemd-Hardening-Flags.
- Copy-paste von Systemd-Sicherheitsoptionen in jede Service-Datei führt zu Drift und vergessenen Updates.
- `lib/systemd-hardening.nix` implementiert eine `mkHardened`-Factory-Funktion, die konsistente Baseline-Härtung für alle eigenen Dienst-Definitionen sicherstellt.

## Entscheidung {#entscheidung}

**`mkHardened`-Factory in `lib/systemd-hardening.nix` als Standard-Baseline für alle eigenen systemd-Services.**

### mkHardened Baseline {#mkhardened-baseline}

```nix
# lib/systemd-hardening.nix {#libsystemd-hardeningnix}
mkHardened = { caps ? [], rw ? [], mdwx ? true }: {
  ProtectSystem      = "strict";   # Dateisystem read-only außer Ausnahmen
  ProtectHome        = true;       # /home komplett ausgeblendet
  PrivateTmp         = true;       # Eigenes /tmp, nicht das des Systems
  PrivateDevices     = true;       # Kein Zugriff auf /dev (außer Standard-Pseudo-Devices)
  ProtectKernelTunables = true;    # Keine sysctl-Schreibzugriffe
  ProtectKernelModules  = true;    # Kein modprobe/insmod
  ProtectControlGroups  = true;    # Keine cgroup-Manipulation
  NoNewPrivileges    = true;       # Kein setuid/sudo-Eskalation
} // optionalAttrs mdwx {
  MemoryDenyWriteExecute = true;   # Kein JIT/Shellcode in Speicher
  DevicePolicy = "closed";         # Nur explizit erlaubte Devices
} // optionalAttrs (caps != []) {
  CapabilityBoundingSet = caps;    # Capabilities auf Whitelist beschränken
  AmbientCapabilities   = caps;
} // optionalAttrs (rw != []) {
  ReadWritePaths = rw;             # Explizite Schreib-Ausnahmen
};
```nix

### Verwendung im Dienst {#verwendung}

```nix
# Beispiel: ein eigener Service in modules/60-apps/ {#beispiel-ein-eigener-service-in-modules60-apps}
systemd.services.mein-dienst = {
  serviceConfig = lib.mkMerge [
    (hardening.mkHardened {
      rw = [ "/var/lib/mein-dienst" ];
    })
    {
      DynamicUser   = true;    # Flüchtiger System-User, keine permanente UID
      StateDirectory = "mein-dienst";
      ExecStart = "${pkgs.mein-paket}/bin/mein-dienst";
    }
  ];
};
```

### DynamicUser-Pattern {#dynamicuser}

`DynamicUser = true;` erzeugt einen temporären System-User ohne persistente UID und ohne Shell. Der Dienst kann nie dauerhaft in das System schreiben. Kombiniert mit `ProtectHome = true;` kann ein kompromittierter Dienst keine SSH-Keys oder `.bashrc`-ähnliche Persistenz-Mechanismen ausnutzen.

> **Ausnahme:** Dienste die Hardware-Zugriff brauchen (Jellyfin → `/dev/dri`, Home Assistant → `/dev/ttyUSB*`) benötigen `PrivateDevices = false` und explizite Gruppe-Mitgliedschaften. Diese Ausnahmen werden pro Service dokumentiert.

### mdwx = false für JIT-Dienste {#mdwx}

`MemoryDenyWriteExecute` blockiert JIT-Compiler in Laufzeit-Umgebungen (.NET, Node.js, Java). Für solche Dienste: `mkHardened { mdwx = false; }`.

## Diagnose {#diagnose}

**Symptom:** Dienst schlägt mit Permission-Fehlern fehl, Schreibzugriff auf eigene Daten verweigert.

```bash
# Welche Hardening-Flags sind aktiv? {#welche-hardening-flags-sind-aktiv}
systemctl show jellyfin | grep -E 'ProtectSystem|ProtectHome|NoNew|DynamicUser|MemoryDeny'

# Wurde ein Schreibversuch auf geschütztes FS blockiert? {#wurde-ein-schreibversuch-auf-geschuetztes-fs-blockiert}
journalctl -u mein-dienst -n 50 --no-pager | grep -iE "permission denied|read-only|not permitted"
```text

**Erwarteter Output bei fehlender ReadWritePaths-Ausnahme:**
```
mein-dienst[1234]: Error: open /var/lib/mein-dienst/data.db: read-only file system
```bash

## Fix {#fix}

```bash
# 1. Fehlendes Schreib-Verzeichnis in mkHardened-rw eintragen: {#1-fehlendes-schreib-verzeichnis-in-mkhardened-rw-eintragen}
# mkHardened { rw = [ "/var/lib/mein-dienst" "/run/mein-dienst.sock" ]; } {#mkhardened-rw-varlibmein-dienst-runmein-dienstsock}

# 2. Hardware-Zugriff: PrivateDevices = false + DeviceAllow {#2-hardware-zugriff-privatedevices-false-deviceallow}
# serviceConfig.DeviceAllow = [ "/dev/dri rw" ]; {#serviceconfigdeviceallow-devdri-rw}

# 3. Dry-build {#3-dry-build}
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh

# 4. Nach Switch Flags prüfen {#4-nach-switch-flags-pruefen}
systemctl show mein-dienst | grep -E 'ProtectSystem|ProtectHome|NoNew'
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Kompromittierter Dienst kann nicht auf SSH-Keys, Tokens anderer Dienste oder das Home-Verzeichnis zugreifen.
- `ProtectKernelModules` verhindert, dass ein Dienst via `insmod` Kernel-Code injiziert.
- `NoNewPrivileges` blockiert SetUID-Eskalation (kein `sudo` aus dem Dienst heraus).
- Factory-Funktion stellt sicher, dass kein Service die Baseline versehentlich vergisst.

### Negativ / Trade-offs {#negativ}

- Dienste müssen ihre `ReadWritePaths` explizit deklarieren — mehr Konfigurationsaufwand.
- `MemoryDenyWriteExecute = true` bricht JIT-basierte Runtimes (.NET, JVM) — `mdwx = false` nötig.
- `DynamicUser` ist inkompatibel mit statischen Dateiberechtigungen die eine feste UID erwarten — dann `UMask + StaticUser` nutzen.

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Factory-Funktion | `lib/systemd-hardening.nix` |
| Verwendende Module | `modules/60-apps/`, `modules/50-media/`, `modules/80-agents/` |

### Verifikation {#verifikation}

```bash
# Baseline-Flags eines gehärteten Dienstes prüfen {#baseline-flags-eines-gehaerteten-dienstes-pruefen}
systemctl show pocket-id | grep -E 'ProtectSystem|NoNewPrivileges|ProtectHome'
# Erwartete Ausgabe: ProtectSystem=strict, NoNewPrivileges=yes, ProtectHome=yes {#erwartete-ausgabe-protectsystemstrict-nonewprivilegesyes-protecthomeyes}
```text

## Alternativen verworfen {#alternativen}

- **Manuelle serviceConfig pro Datei** — Drift-anfällig, vergessene Updates. Abgelehnt.
- **`systemd-analyze security <service>`-gesteuertes Hardening** — nützlich zur Verifikation, aber kein Framework für konsistente Baseline. Ergänzend verwendbar.
- **Firejail/AppArmor/SELinux** — komplexer, benötigt Profil-Pflege pro Anwendung. Systemd-native Härtung ist ausreichend für Homelab-Szenario.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-05 | Initial (aus Grok-Systemanalyse destilliert) |

## Siehe auch {#siehe-auch}

- [ADR-2026 — Kernel-Härtung sysctl](2026-kernel-hardening-sysctl.md) — Kernel-Ebene als Basis
- [ADR-2027 — Kernel-Slim](2027-kernel-slim-module-policy.md) — Modul-Blacklisting als weitere Schicht
- [ADR-003 — OOM cgroup-Isolation](003-oom-cgroup-isolation.md) — Ressourcen-Isolation via Memory-Limits
- [ADR-007 — Dendritische Module](007-dendritic-one-file-per-service.md) — eine Datei pro Dienst als Kontext
- [GUIDE-kernel-hardening.md](../guides/GUIDE-kernel-hardening.md) — Betriebsguide
