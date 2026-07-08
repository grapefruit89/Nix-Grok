---
meta:
  role: doc
  purpose: systemd-networkd-wait-online auf Headless-Server deaktivieren — 2min Switch-Timeout Fix
  status: accepted
  date: 2026-07-08
  error_pattern: "Job for systemd-networkd-wait-online.*failed|A stop job is running for.*wait-online"
  quick_fix: "Nach switch: systemctl reset-failed; der Timeout tritt während switch auf, nicht danach"
  services: [systemd-networkd-wait-online]
  betrifft:
    - modules/20-security/27-hardened-core.nix
    - modules/10-network/16-vpn.nix
  docs:
    - docs/adr/2026-kernel-hardening-sysctl.md
    - docs/adr/1033-oauth2-proxy-forward-auth.md
  tags:
    - systemd
    - network
    - headless
    - rebuild
    - wireguard
---

# ADR-2030: systemd-networkd-wait-online auf Headless-Server deaktivieren {#adr-2030}

| Feld | Wert |
|------|------|
| **Status** | Accepted |
| **Datum** | 2026-07-08 |
| **Host** | q958 |

---

## Kontext {#kontext}

Jeder `nixos-rebuild switch` auf q958 schlägt mit **exit code 4** fehl und blockiert für
**exakt 120 Sekunden**. Das Fehler-Log zeigt:

```
switch-to-configuration: warning: the following units failed: systemd-networkd-wait-online.service
```

`switch-to-configuration` exit code 4 = "some units failed to start" — aber nixos-rebuild
selbst gibt 0 zurück. Die 2 Minuten entstehen durch den Default-Timeout von
`systemd-networkd-wait-online`.

**Warum blockiert wait-online?** q958 nutzt Privado WireGuard VPN (`networking.wg-quick.interfaces.privado`).
Das NixOS wg-quick-Modul setzt automatisch:
```nix
# nixpkgs/nixos/modules/services/networking/wg-quick.nix Zeile 457:
systemd.network.wait-online.ignoredInterfaces = builtins.attrNames cfg.interfaces;
# → ignoredInterfaces = ["privado"]
```

Das triggert im networkd-Modul:
```nix
# nixpkgs/nixos/modules/system/boot/networkd.nix Zeile 4196-4203:
systemd.services.systemd-networkd-wait-online = {
  inherit (cfg.wait-online) enable;
  wantedBy = [ "network-online.target" ];  # ← UNCONDITIONAL
  serviceConfig.ExecStart = [ "" "${systemd}/lib/systemd/systemd-networkd-wait-online --timeout=120 --ignore=privado" ];
};
```

Während eines `nixos-rebuild switch` ist der Privado-VPN-Tunnel nicht aktiv (wg-quick startet
erst nach network-online.target) → wait-online wartet 120 Sekunden → Timeout → exit 4.

---

## Entscheidung {#entscheidung}

**Zwei NixOS-Optionen kombinieren**, beide sind nötig:

```nix
# modules/20-security/27-hardened-core.nix
systemd.network.wait-online.enable = false;
systemd.services."systemd-networkd-wait-online".wantedBy = lib.mkForce [ ];
```

### Warum beide Zeilen? {#warum-beide}

**`enable = false` allein reicht nicht:**
Das NixOS networkd-Modul setzt `wantedBy = ["network-online.target"]` *ohne* Bedingung an
`enable`. Selbst wenn `enable = false` das Unit-File unterdrückt, bleibt das WantedBy-Symlink
in `/etc/systemd/system/network-online.target.wants/` bestehen. Systemd startet den Service
trotzdem, sobald `network-online.target` aktiviert wird.

**`wantedBy = lib.mkForce []` allein reicht nicht:**
Ohne `enable = false` würde das Override-File mit `ExecStart` und `--timeout=120` generiert.
Falls ein anderer Mechanismus die Unit doch startet, würde sie wieder 2 Minuten blockieren.

**Zusammen:** Kein WantedBy-Symlink + kein Override-File = Unit startet nie.

---

## Bugs bei den Deaktivierungsversuchen {#bugs}

### Fehlversuch 1: `wantedBy = lib.mkForce []` allein {#fehlversuch-1}

**Symptom:** Gleiche Closure wie vorher (switch hängt weiterhin).
**Ursache:** Ohne `enable = false` bleibt das Override-File mit `ExecStart` aktiv; der Service
kann über andere Wege (z.B. `systemctl start`) gestartet werden.

### Fehlversuch 2: `systemd.network.wait-online.enable = false` allein {#fehlversuch-2}

**Symptom:** Gleiche Closure wie vorher — kein Effekt sichtbar.
**Ursache:** `enable = false` propagiert als `inherit (cfg.wait-online) enable` in die Service-Definition,
aber `wantedBy = ["network-online.target"]` bleibt unconditional gesetzt (networkd.nix Zeile 4198).
Das WantedBy-Symlink existiert weiterhin → Service wird gestartet.

### Fehlversuch 3: `unitConfig.ConditionPathExists = lib.mkForce "/nonexistent"` {#fehlversuch-3}

**Symptom:** ConditionPathExists erscheint **nicht** in der generierten override.conf.
**Ursache:** `lib.mkForce` auf einen String-Wert *innerhalb* eines `attrsOf`-Attrsets hat keine
Wirkung. `lib.mkForce "string"` erstellt einen Priority-Wrapper, keine überlegene Merge-Priorität
für Attrset-Keys. Das NixOS Unit-File-Generator ignoriert den Wrapper und übernimmt den Wert nicht.

Lesson: `lib.mkForce` ist nur auf **Options-Ebene** wirksam (`systemd.services.<name>.wantedBy`),
nicht auf Werte innerhalb von `attrsOf`-Options (`systemd.services.<name>.unitConfig.key`).

### Fehlversuch 4: Gleiche Closure nach Switch {#fehlversuch-4}

**Symptom:** `nixos-rebuild switch` baut Closure `kvm854ailzxpkfp2r8a8hqc4ifgccnr8` — identisch
mit dem vorherigen Switch.
**Ursache:** Wenn Nix-Config-Änderungen durch Merge-Prioritäten wieder aufgehoben werden (wie
in Fehlversuchen 1-3), ist das evaluierte Nix-Ergebnis identisch → gleiche Content-Hash →
gleiche Store-Path.
**Diagnose:** `nix-store --query --hash /run/current-system` vor und nach Dry-Build vergleichen.

---

## Diagnose {#diagnose}

**Symptom:** `nixos-rebuild switch` dauert 2+ Minuten extra, endet mit Warning:

```bash
journalctl -u systemd-networkd-wait-online -n 10 --no-pager
# Erwarteter Output bei Timeout:
# systemd-networkd-wait-online[...]: Timeout waiting for network connectivity.

# WantedBy-Symlink prüfen (nach Fix sollte er weg sein):
ls -la /etc/systemd/system/network-online.target.wants/ | grep wait-online

# Override-File prüfen (nach Fix leer oder nicht existent):
cat /etc/systemd/system/systemd-networkd-wait-online.service.d/overrides.conf 2>/dev/null || echo "kein Override"
```

---

## Fix {#fix}

```nix
# modules/10-network/16-vpn.nix — innerhalb lib.mkIf config.my.services.privado-vpn.enable { ... }
systemd.services."systemd-networkd-wait-online".wantedBy = lib.mkForce [ ];
```

**Wichtig: Wo der Fix NICHT hingehört (und warum):**
- `27-hardened-core.nix` ist falsch: dort ist der Block in `lib.mkIf cfg.enable` eingebettet, wobei
  `cfg.enable = hardened.enable = erstAb 9`. Bei Stufe 8 = `lib.mkIf false {}` → toter Code.
- `16-vpn.nix` ist korrekt: `privado-vpn.enable = erstAb 6`, bei Stufe 8 aktiv. Ursache und Fix
  im gleichen Modul → klar und wartbar.

```bash
# Strukturelle Verifikation OHNE Switch (sicherer als direkter Switch):
sudo nixos-rebuild build --flake /etc/nixos#q958 --impure
ls result/etc/systemd/system/network-online.target.wants/
# Erwartete Ausgabe: leer (Verzeichnis existiert nicht)

# Switch (kein tmux/systemd-run nötig — Switch dauert jetzt <60s):
nsw
# oder direkt: sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure

# Verifikation nach Switch:
ls /etc/systemd/system/network-online.target.wants/ 2>/dev/null || echo "Verzeichnis fehlt — korrekt"
```

### Fehlgeschlagene Ansätze beim Rebuild-Script {#script-bugs}

Bei der Suche nach tmux-Alternativen wurden drei Varianten versucht, die alle scheiterten:

| Versuch | Kommando | Fehler |
|---------|----------|--------|
| 1 | `systemd-run --wait --pipe nixos-rebuild switch` | `[Errno 2] No such file or directory: 'test'` — nixos-rebuild ruft intern selbst `systemd-run --pipe` auf; nested `--pipe` Units schlagen fehl |
| 2 | `systemd-run --property=StandardOutput=file:/tmp/...` | Exit 209/STDOUT — systemd kann die Logdatei nicht öffnen wenn als Property angegeben |
| 3 | `systemd-run sh -c "nixos-rebuild switch > log 2>&1; echo $?"` | 13ms, Silent success — `sh` läuft im systemd-PATH ohne nixos-rebuild; `echo $?` maskiert exit 127 als 0 |

**Lösung:** Kein Wrapper. `nixos-rebuild switch` direkt, ohne systemd-run. `scripts/nixos-rebuild-safe.sh` nutzt jetzt `nixos-rebuild switch ... | tee /tmp/nixos-switch.log` direkt.

---

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- `nixos-rebuild switch` dauert nicht mehr 2 Minuten länger als nötig
- Kein spurioser exit code 4 mehr
- Services die `wants = ["network-online.target"]` haben (Pocket-ID, oauth2-proxy)
  starten sofort — network-online.target wird von anderen Quellen erfüllt

### Negativ / Trade-offs {#negativ}

- `systemd-networkd-wait-online` läuft nicht mehr → Services die echtes Warten auf
  Netzwerkverfügbarkeit brauchen, haben diese Garantie nicht mehr
- Auf q958 unkritisch: Ethernet ist beim Boot immer verfügbar; wg-quick startet selbst
  nach network-online.target über `after = ["network-online.target"]`

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| **Fix (aktiv)** | `modules/10-network/16-vpn.nix` — innerhalb `privado-vpn.enable` Block |
| Toter Code (entfernt) | `modules/20-security/27-hardened-core.nix` — war in `mkIf (erstAb 9)` = false |
| Root Cause (nixpkgs) | `nixos/modules/services/networking/wg-quick.nix` Zeile 457 |
| Root Cause (nixpkgs) | `nixos/modules/system/boot/networkd.nix` Zeile 4196-4203 |

### Verifikation {#verifikation}

```bash
# Nach Switch: kein WantedBy-Symlink
ls /etc/systemd/system/network-online.target.wants/ | grep -c wait-online
# Erwartete Ausgabe: 0
```

---

## Alternativen verworfen {#alternativen}

- **`systemd.network.wait-online.timeout = 1`** — Service scheitert nach 1s, exit code 4 bleibt aber.
  Kürzer ja, aber Problem nicht gelöst. Abgelehnt.
- **`systemd.network.wait-online.anyInterface = true`** — wartet auf ANY Interface (lo/eth0);
  würde sofort succeeden. Aber Ethernet könnte theoretisch kurz offline sein. Weniger präzise als
  vollständige Deaktivierung. Abgelehnt.
- **`ConditionPathExists` im unitConfig** — `lib.mkForce` auf String-Wert in `attrsOf` hat keine
  Wirkung (→ Bug 3). Funktioniert nicht. Abgelehnt.

---

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-08 | Initial — Root Cause im nixpkgs-Source analysiert, 4 Fehlversuche dokumentiert |
| 2026-07-08 | Fix von 27-hardened-core.nix → 16-vpn.nix verschoben (erstAb-9-Bug) |
| 2026-07-08 | Rebuild-Script: tmux/systemd-run entfernt — direkter switch nach wait-online-Fix |

---

## Siehe auch {#siehe-auch}

- [ADR-2026 — Kernel Hardening](2026-kernel-hardening-sysctl.md) — 27-hardened-core.nix Kontext
- [ADR-1033 — oauth2-proxy](1033-oauth2-proxy-forward-auth.md) — Service der durch wait-online blockiert wurde
