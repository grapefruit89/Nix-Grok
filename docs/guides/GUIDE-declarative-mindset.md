---
meta:
  role: doc
  purpose: Leitfaden für AI-Agenten und Contributor — deklarativer NixOS-Mindset, Escape-Hatch-Regeln, Checkliste
  tags:
    - agents
    - declarative
    - review
---

# GUIDE: Deklarativer NixOS-Mindset

**Für**: AI-Agenten (Claude, Grok, etc.) und menschliche Contributor beim Code-Review.

**Philosophie**:
> NixOS ist kein imperativer Konfigurationsmanager. Systemzustand wird über `options` + `config` ausgedrückt.
> Was nicht rein deklarativ ausdrückbar ist, wird über kontrollierte Escape-Hatches explizit und dokumentiert gemacht.

---

## 1. Was ist imperativ — und warum verboten?

| Muster | Warum problematisch | Erlaubte Alternative |
|--------|---------------------|----------------------|
| `activationScripts` ohne Dokumentation | Filesystem-Mutation bei jedem switch | Begründung + `lib.mkIf` zum Deaktivieren |
| `writeShellScript` mit `cp`, `sed -i`, persistenter State | State drift, nicht reproduzierbar | `systemd.services` mit `StateDirectory` + `tmpfiles` |
| Hardcodierte Werte ohne Ableitung oder Kommentar | Keine Override-Möglichkeit, versteckte Annahmen | `mkOption` wenn maschinenvariant; Kommentar wenn Single-Host |
| `builtins.readFile`/`readDir` auf Runtime-Pfade (`/etc`, `/var`) | Verletzt Evaluation-Purity | `my.*`-Optionen |
| Manuelle Rebuilds ohne `scripts/nixos-rebuild-safe.sh` | Umgeht dry-build Gate | Immer über Safe-Script oder `nh` |

**Flaggen beim Review**:
> Neue `activationScripts`, `writeShellScript` mit Filesystem-Mutation, oder `builtins.readFile` auf `/etc`/`var`/`.git` **ohne** klare Begründung → sofort flaggen.

---

## 2. Erlaubte Escape-Hatches (mit Begründung)

### `system.activationScripts.preCommitInstall` (`01-core.nix`)

**Warum imperativ**: `.git/hooks/` liegt außerhalb des Nix-Store. Nix kann dort nicht schreiben.

**Warum erlaubt**: Offizieller NixOS-Mechanismus für "one-time setup". Erzwingt nixfmt/statix/deadnix (POL-FMT-010..012) nach jedem switch automatisch.

**Bedingungen**: Nur aktiv wenn `my.mode == "development"` (kein Overhead auf Produktionsservern).

### `builtins.readDir`/`readFile` in `02-nixmeta-ban.nix` + `07-structure-validation.nix`

**Warum scheinbar imperativ**: Filesystem-Scan zur Evaluierungszeit.

**Warum erwünscht**: Das ist **keine Runtime-Mutation**, sondern deklarative Selbstpolizei. Build bricht hart bei Verstoß.

**Regel**: Nur in `00-core/` als Guardrail erlaubt. In Anwendungsmodulen (`50-media/`, `60-apps/` etc.) verboten.

---

## 3. Magic Numbers — wann Option, wann Kommentar?

**Diskriminierender Test**: *Wird dieser Wert jemals zwischen Maschinen, `my.mode`-Stufen oder Rebuilds variieren?*

- **Ja, maschinenabhängig** → `mkOption` mit `default`, ableitbar aus `my.configs.hardware.*`
- **Ja, aber selten geändert** → Kommentar erklärt Herkunft, bei Bedarf Option hinzufügen
- **Nein, Single-Host-Konstante** → Kommentar reicht

**Beispiele aus diesem Repo**:

| Wert | Lösung | Begründung |
|------|--------|------------|
| `min-free`/`max-free` | Abgeleitet aus `nixStoreGB * 1073741824 / 100` | Skaliert mit Partitionsgröße, in `profile.nix` |
| `max-jobs`/`cores` | Abgeleitet aus `ramGB` | Bereits RAM-adaptiv |
| `memoryPercent` (ZRAM) | Abgeleitet aus `ramGB` (75/50/25) | Bereits RAM-adaptiv |
| `configurationLimit = 5` | Kommentar (ESP-Größe) | Single-Host, ESP = 1 GB auf q958 |
| `vm.swappiness = 180` | Kommentar (ZRAM-spezifisch, Bereich 0–200) | Single-Config, erklärt warum 180 |
| `SystemMaxUse=500M` (journald) | Kommentar | Single-Host-Konstante |
| `timeout = 3600` | Kommentar | Selten geändert |

---

## 4. Muster: maschinenabhängige Werte korrekt ableiten

**So sieht es richtig aus** (Vorlage aus `01-core.nix`):

```nix
# In machines/<host>/profile.nix:
hardware = {
  ramGB = 32;
  nixStoreGB = 468;  # /dev/sda2, Stand YYYY-MM
};

# In machines/<host>/default.nix:
my.configs.hardware = {
  ramGB = p.hardware.ramGB;
  nixStoreGB = p.hardware.nixStoreGB;
};

# In modules/00-core/01-core.nix:
let
  nixStoreGB = config.my.configs.hardware.nixStoreGB;
in
  min-free = nixStoreGB * 1073741824 / 100;  # 1% des Stores
  max-free = nixStoreGB * 1073741824 / 50;   # 2% des Stores
```

**Neues Hardware-Attribut hinzufügen**: immer `profile.nix` → `default.nix` → `01-core.nix options` → Nutzung im Modul.

---

## 5. `my.mode` — korrekte Nutzung

`my.mode` ist **kein toter Code**. Es wird aktiv in folgenden Modulen genutzt:
- `lib/nftables-rules.nix` — SSH-Port-Auswahl
- `modules/20-security/` — Hardening-Defaults
- `modules/30-storage/` — Impermanence-Default
- `modules/40-observability/` — Runtime-Guard
- `machines/q958/rollout.nix` — `stufe >= 9 → production`
- `modules/90-policy/` — Security-Assertions

**In `01-core.nix`** steuert es: `system.activationScripts.preCommitInstall` (nur in `development`).

---

## 6. Review-Checkliste

- [ ] Keine neuen `activationScripts` ohne Begründung + `lib.mkIf`-Gate
- [ ] Keine `builtins.readFile`/`readDir` außerhalb `00-core/` Guardrails
- [ ] Magic Numbers: maschinenabhängig → ableiten; Single-Host → kommentieren
- [ ] Neue Ports → immer `my.ports.<name>` in `08-ports.nix`
- [ ] Neue UID/GID → `my.users.registry`/`my.groups.registry` (ADR-011)
- [ ] Hardware-abhängige Werte → `profile.nix` → `default.nix` → Option → Ableitung

---

## 7. Cross-Layer Dependencies

`04-services-spec.nix` referenziert `config.my.ingress.fromSpec.enable` (definiert in höherer Schicht). Solche Upstream-Abhängigkeiten sind erlaubt — NixOS löst sie lazy auf. Beim Review: sicherstellen dass das referenzierte Modul im Flake eingebunden ist.

---

## 8. Layer-Review: 20-security (Juli 2026)

Sicherheitskritische Module: Firewall, SSH, LUKS-Unlock, Kernel-Hardening, Fail2ban.

### 8.1 Imperative Escape-Hatches (vollständig)

| Stelle | Muster | Bewertung |
|--------|--------|-----------|
| `15-firewall.nix` `nftables-geoip-update` Service+Timer | `writeShellScript` + `curl` + `nft -f` wöchentlich | Kontrollierter Escape-Hatch für externe Blocklisten. Runtime-Abhängigkeit auf ipdeny.com. Hinter `my.security.firewall.geoipAutoUpdate.enable` (default: true) deaktivierbar. |
| `20-security.nix` `dropbear-rescue` `ExecStartPre` | `writeShellScript` für `authorized_keys` Prep | Akzeptabel: `StateDirectory = "dropbear"` bereits gesetzt, Prep ist minimal und idempotent. |
| `21-sovereign-unlock.nix` `qrFallbackScript` | `writeShellScript` QR-Code auf TTY im initrd | Notfall-Fallback im frühen Boot. Akzeptabel und gut isoliert. |
| `22-fail2ban.nix` `environment.etc."fail2ban/..." .text` | Deklaratives Droppen von Filter/Action-Config | **Musterbeispiel** — kein Imperativismus, `environment.etc` ist der richtige Weg. |

**Neue Agentenregel**: `writeShellScript` in `ExecStart`/`ExecStartPre` → prüfen ob persistenter State mutiert wird. Wenn ja: dokumentieren + Deaktivierungsoption.

### 8.2 Was Grok falsch lag (nicht nachahmbar)

| Grok-Behauptung | Realität |
|----------------|----------|
| "`webRateLimit = "100/minute"` ist Magic Number (Prio Mittel)" | Bereits `mkOption` mit Assertion (Zeile 79–83, 122–124) |
| "Fail2ban: viele Magic Strings/Ints (bantime, multipliers...)" | Bereits vollständig mit `mkOption` parametrisiert (bantime, findtime, maxretry, banaction, banIncrementEnable, banIncrementMultipliers...) |
| "Port 2222: dupliziert (Prio Hoch)" | Zwei getrennte Dienste (initrd-SSH ≠ stage-2 dropbear), zeitlich disjunkt, beide schon `mkOption`. Kein Bug. |
| "dropbear `ExecStartPre` modernisieren mit `LoadCredential`" | `StateDirectory = "dropbear"` bereits gesetzt — kein Handlungsbedarf. |

### 8.3 Positiv (vorbildlich für andere Layer)

- `my.mode` wird in `20-security` **korrekt genutzt** — SSH-Port, Sovereign-Unlock, Kernel-Params reagieren auf `development` vs. `production`. Das Muster das in `00-core` fehlt, ist hier Realität.
- Starke Assertions: AuthorizedKeys-Pflicht, Tang/SSH-Keys bei Sovereign-Unlock.
- `kfence.sample_interval=100` bereits kommentiert: `# KFENCE: 1% Sampling für UAF/OOB-Detection`.
- Kernel-Blacklist in `26-kernel-hardening.nix` ist vollständig kommentiert pro Modul.

### 8.4 Was tatsächlich umgesetzt wurde

- `geoipAutoUpdate.enable` Option + `lib.mkIf`-Gate für Service+Timer
- Kommentare zu `rmem_max`, `wmem_max`, `tcp_max_syn_backlog`
- OOMScoreAdjust für `technitium-dns-server` (-300) und `redis-valkey` (-600)

---

**Stand**: 2026-07-06 | **Maintainer**: Moritz + AI-Agenten
