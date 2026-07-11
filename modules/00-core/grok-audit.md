# Audit: modules/00-core
Datum: 2026-07-10
Auditor: Grok

## Übersicht

`modules/00-core/` ist die immer aktive Fundamentschicht des q958-Homelabs. Zehn Nix-Module plus `default.nix` definieren das globale Optionschema (`my.*`), zentrale Port- und Service-Spec-Registries, Build-Time-Guardrails (NIXMETA-Verbot, Verzeichnisstruktur), Secrets-Infrastruktur (systemd-creds), Boot-Health-Checks und Dev-Tooling (Nix-Tuning, ZRAM, CLI-Aliases).

Die Architektur ist durchdacht und folgt klaren SSoT-Prinzipien. Die Module sind überwiegend schlank und delegieren Logik an `lib/`. Auffälligkeiten betreffen vor allem Dokumentationsdrift (README), eine Konfigurationsüberlagerung bei `boot-safeguard`, und einige bewusste Konvention-Verletzungen (HA-Port 8123 außerhalb der Port-Registry).

---

## Datei-Audits

### default.nix
**Zweck:** Aggregiert alle 00-core-Untermodule in fester Reihenfolge (01→09). Einstiegspunkt für `machines/q958/default.nix`.

**Bewertung:** ✓

**Findings:**
- Import-Reihenfolge ist logisch: Options/Schema zuerst (01), Guardrails (02, 07), Registries (03, 04, 08), Infrastruktur (05, 06), Tooling (09).
- YAML-Header-Kommentar erwähnt noch „SOPS" — tatsächlich ist `05-creds.nix` (systemd-creds) importiert.
- Keine `rollout.stufe`-Gating — korrekt für Layer 0.

**Abhängigkeiten:** Alle `./0*.nix`-Module im Ordner.

**Empfehlung:** keep as-is (Header-Kommentar optional auf „creds" korrigieren)

---

### 01-core.nix
**Zweck:** Definiert das globale `my.*`-Optionsschema (Locale, Hardware, Server, Netzwerk, Mode) und wendet Basis-Systemconfig an (Timezone, Locale, Keymap, Journald-Limits, nix-ld, Boot-Safeguard).

**Bewertung:** ⚠

**Findings:**
- Zweck ist klar; saubere Trennung: Options hier, Implementierung von Nix-Tuning/ZRAM in `09-nix-tools.nix`, kernel-slim in `20-security/25-kernel-policy.nix`.
- `my.configs.identity.*` und `hardware.*` ohne Defaults — bewusst, Werte kommen aus `machines/q958/default.nix` / `profile.nix`.
- `my.configs.network.dnsBootstrap` mit DoT-SNI-Hostnames ist gut dokumentiert und passt zum v4-only/DoT-Design (ADR-1001).
- `my.configs.network.ipv6.*` sind deklarative Hooks für bewusst deaktiviertes IPv6 — kein Fehler.
- **Konflikt:** `boot.loader.systemd-boot.configurationLimit` wird hier via `my.core.boot-safeguard` gesetzt, aber `machines/q958/rollout.nix` überschreibt mit `lib.mkForce p.boot.generationLimit` (= 8). `default.nix` setzt `configurationLimit = 15` — dieser Wert greift aktuell nicht. Verwirrende Doppelquelle.
- `my.core.boot-safeguard.configurationLimit` default = 5, `profile.nix` = 8, `default.nix` = 15 — drei verschiedene Werte ohne klare Priorität in der Doku.
- Journald-Limits via `mkDefault` — andere Module können überschreiben.

**Abhängigkeiten:** Keine Lib-Imports. Von `09-nix-tools.nix`, `machines/q958/rollout.nix`, allen Modulen die `my.configs.*` lesen.

**Empfehlung:** minor cleanup — Boot-Generation-Limit auf eine Quelle konsolidieren (entweder nur `profile.nix`/`rollout.nix` oder nur `boot-safeguard`)

---

### 02-nixmeta-ban.nix
**Zweck:** Build-Time-Assertion, die `# !type`-NIXMETA-Marker im gesamten Repo verbietet.

**Bewertung:** ✓

**Findings:**
- Rekursives `readDir`/`readFile` über Repo-Wurzel — erlaubter Guardrail in 00-core (vgl. GUIDE-declarative-mindset).
- Schließt sich selbst, `.git` und `stage-nixos` korrekt aus.
- Pattern `[ \t]*#[ \t]*![a-z]+.*` trifft NIXMETA-Marker, nicht die YAML-`meta:`-Header in anderen Dateien.
- Fehlermeldung verweist auf AGENTS.md — hilfreich.

**Abhängigkeiten:** Repo-Dateisystem via `builtins.readDir`/`readFile`.

**Empfehlung:** keep as-is

---

### 03-uid-registry.nix
**Zweck:** Bindet `lib/uid-registry.nix` als `my.users.registry` / `my.groups.registry` ein und prüft UID/GID-Eindeutigkeit.

**Bewertung:** ✓

**Findings:**
- Dünner, korrekter Wrapper — SSoT bleibt in `lib/uid-registry.nix`.
- Registry ist bewusst partiell (nur *arr-Stack + `secrets-portal`) — nicht jeder Dienst braucht statische UID.
- Assertions prüfen nur Duplikate, nicht Port=UID-Konsistenz (ADR-011 empfiehlt das Schema, ist aber nur für registrierte Einträge relevant).
- `getUser`/`getGroup` mit `throw` sind in der Lib verfügbar, werden hier nicht re-exportiert — Module importieren Lib direkt wenn nötig.

**Abhängigkeiten:** `lib/uid-registry.nix`

**Empfehlung:** keep as-is

---

### 04-services-spec.nix
**Zweck:** Service-Spec-Matrix (`my.services.spec`) als SSoT für Zonen, Ports/Sockets, Ingress-Subdomains. Default-Spec aus `lib/services-spec.nix`, Port-/DNS-Konsistenz-Assertions.

**Bewertung:** ⚠

**Findings:**
- Zweck und Struktur klar; gute Assertions:
  - Port-Duplikate in `my.ports` und `my.services.spec`
  - Caddy aktiv → `my.ingress.fromSpec` muss aktiv sein
  - Subdomain-Abgleich mit `lib/dns-map.nix`
- `mkDefaultSpec` referenziert `config.my.ports` — saubere Verkettung mit `08-ports.nix`.
- **Konventionsabweichung:** `home-assistant` in `lib/services-spec.nix` nutzt hardcodiert `port = 8123` statt `ports.home-assistant` aus `08-ports.nix`. Verstößt gegen Projektregel „alle Ports zentral".
- **Cross-Layer-Abhängigkeit:** Referenziert `config.my.ingress.fromSpec.enable` (definiert in `10-network/1094-ingress.nix`). Bewusst erlaubt (lazy eval), aber 00-core hängt von 10-network-Option ab.
- `postgresql` in Spec-Matrix, aber `postgresql.enable = false` in rollout — Spec-Eintrag ist trotzdem sinnvoll für künftige Aktivierung.

**Abhängigkeiten:** `lib/services-spec.nix`, `lib/dns-map.nix`, `config.my.configs.identity.domain`, `config.my.ports`, `config.my.ingress.fromSpec` (10-network)

**Empfehlung:** minor cleanup — `home-assistant`-Port in `08-ports.nix` aufnehmen und Spec anbinden

---

### 05-creds.nix
**Zweck:** systemd-creds Credential-Store (`my.creds`) + permanente sops-nix-Verbots-Assertion.

**Bewertung:** ✓

**Findings:**
- sops-Verbot ist immer aktiv (unabhängig von `my.creds.enable`) — korrekte Policy-Entscheidung für q958.
- `storeDir`, `useTpm`, `keys`-Liste gut dokumentiert.
- `activationScripts.credentialCheck` listet fehlende `.cred`-Dateien mit Siegel-Anleitung — sehr hilfreich für Rotation.
- **Soft-Check:** Script setzt `_missing=1`, bricht den Build aber nicht ab (`exit 1` fehlt). Passt zur schrittweisen Migration (Stufe 8), bedeutet aber: fehlende Secrets werden erst zur Laufzeit sichtbar.
- TPM-Pakete nur bei `useTpm = true` — korrekt.
- `default.nix` listet bereits 7 Keys in `my.creds.keys` — Store ist vorbereitet, Portal-Aktivierung fehlt noch (laut Handout).

**Abhängigkeiten:** `config.sops.enable` (Verbot), `pkgs.tpm2-*` (optional)

**Empfehlung:** keep as-is (optional: harter Build-Fail ab `my.creds.enable` + Stufe ≥ 8)

---

### 06-boot-watchdog.nix
**Zweck:** Post-Boot Health-Check (Timer + Oneshot) für kritische Dienste (Blocky, PostgreSQL, Caddy). Setzt Restart-Policies für diese Dienste.

**Bewertung:** ⚠

**Findings:**
- Timer `OnBootSec` mit konfigurierbarer Grace-Period (default 180s) — sinnvolles Fail-Fast-Muster.
- `requirePostgresql`/`requireCaddy`/`requireBlocky` defaulten auf jeweiligen `enable`-Flags — gut.
- **Scope-Creep:** Enthält dienstspezifische Logik:
  - PostgreSQL `Restart=always` (OOM-Resilienz)
  - Caddy `requires postgresql` wenn Linkwarden aktiv
  - Restart-Policies für Caddy/Blocky
  Diese gehören architektonisch eher in `10-network/` bzw. `50-media/` — überraschend in 00-core.
- Oneshot-Fehler (`exit 1`) markiert Service als failed, löst aber keinen Reboot/Panic aus — README behauptet fälschlich „Panic bei Kernel-Oops".
- PostgreSQL-Restart-Policy nur aktiv wenn `boot-watchdog.enable` — Kopplung zwei unabhängiger Concerns.

**Abhängigkeiten:** `config.my.services.postgresql/blocky`, `config.services.caddy`, `config.my.services.linkwarden`, `pkgs.systemd`

**Empfehlung:** minor cleanup — dienstspezifische Restart/Requires-Logik in jeweilige Domänenmodule verschieben; Health-Check hier behalten

---

### 07-structure-validation.nix
**Zweck:** Build-Time-Assertions für `modules/`-Top-Levelstruktur: nur nummerierte Unterordner, jedes mit `default.nix`, keine lose Dateien.

**Bewertung:** ✓

**Findings:**
- Whitelist der 10 Domänenordner ist vollständig und aktuell.
- Prüft nur `modules/`-Root — Dateien innerhalb von Unterordnern (z. B. verwaiste `.nix` ohne Import) werden nicht erkannt. Bewusste Scope-Begrenzung.
- Klare Fehlermeldungen mit Handlungsanweisung (neuen Ordner in `allowedDirs` eintragen).
- Keine Config-Section nötig — reine Assertion.

**Abhängigkeiten:** `builtins.readDir` auf `modules/`

**Empfehlung:** keep as-is

---

### 08-ports.nix
**Zweck:** Zentrale Port-Registry (`my.ports.*`) — Single Source of Truth für alle TCP-Ports.

**Bewertung:** ⚠

**Findings:**
- Gut strukturiert mit Bereichs-Kommentaren (1xxx Infra, 4xxx Observability, 5xxx Media, 6xxx Apps, 7xxx Admin).
- 30+ Ports definiert, alle mit `lib.types.port` und Beschreibung.
- **Lücken in der Registry** (Ports existieren in anderen Modulen, aber nicht hier):
  - `8123` — Home Assistant (`home-assistant.nix`, `services-spec.nix`)
  - `8787` — Hermes (`60-apps/default.nix`)
  - `10200/10201/10300` — Wyoming Voice (`voice-assistant.nix`)
  - `9100` — node-exporter (`44-metrics.nix`)
  - `2222` — Dropbear rescue (`20-security/`)
  - `51820` — Netbird/WireGuard (`1096-vpn.nix`)
- Lücke bei `6004` zwischen paperless (6003) und filebrowser (6005) — vermutlich reserviert, undokumentiert.
- Keine Duplikat-Assertion hier — liegt korrekt in `04-services-spec.nix` via `portRegistryAssertion`.
- Options-only — korrekt, keine Config.

**Abhängigkeiten:** Keine. Konsumiert von praktisch allen Service-Modulen.

**Empfehlung:** minor cleanup — fehlende Ports ergänzen (mindestens HA 8123); Lücke 6004 dokumentieren oder befüllen

---

### 09-nix-tools.nix
**Zweck:** Nix-Store-Tuning, Dev-Toolchain (nixfmt/statix/deadnix, moderne CLI-Tools), Bash-Aliases, pre-commit-Hooks, ZRAM-Swap.

**Bewertung:** ✓

**Findings:**
- RAM-skalierte `max-jobs`/`cores` (≤4 GB → 1 Job, ≤8 GB → 2, sonst 4) — sinnvoll für q958.
- GC-Trigger aus `nixStoreGB` (1%/2% des Stores) — elegant maschinenskalierbar.
- `daemonCPUSchedPolicy = idle` wenn `daemonLowPriority` — schont Homelab-Dienste während Builds.
- Shell-Aliases nur via `programs.bash.shellAliases` — betrifft interaktive Bash, nicht Skripte.
- `nsw`/`ntest`-Aliases zeigen auf `nixos-rebuild-safe.sh` — konsistent mit Projektregel.
- pre-commit-Installation via `activationScript` mit `|| true` — idempotent, aber Fehler werden verschluckt.
- ZRAM: `swappiness = 180`, `page-cluster = 0` — bewusste ZRAM-Optimierung, gut kommentiert.
- `trusted-users` enthält `config.my.configs.identity.user` — nötig für Flakes/nix-command als User.
- `keep-outputs`/`keep-derivations = true` — mehr Disk-Verbrauch, schnellere Rebuilds. Dev-Tradeoff.

**Abhängigkeiten:** `config.my.core.nix-tuning`, `config.my.core.zram-swap`, `config.my.configs.hardware.*`, `config.my.mode`, `config.my.configs.identity.user`

**Empfehlung:** keep as-is

---

### README.md
**Zweck:** Dokumentation der 00-core-Schicht.

**Bewertung:** ✗

**Findings:**
- **Stark veraltet:**
  - Referenziert `05-sops.nix` — existiert nicht, heißt `05-creds.nix`
  - Behauptet `01-core.nix` enthält Packages/Aliases/Nix-Tuning/ZRAM — liegt in `09-nix-tools.nix`
  - `06-boot-watchdog` als „Panic bei Kernel-Oops" beschrieben — tatsächlich Post-Boot Service-Health-Check
  - `07-structure-validation` als „Port-Duplikate" beschrieben — das macht `04-services-spec.nix`
  - `03-uid-registry` als „UID=Port=FolderPrefix" — nur teilweise implementiert
- Import-Liste in `default.nix` fehlt `08-ports.nix` und `09-nix-tools.nix`
- Verweist auf `GUIDE-developer-experience.md` und Ports in `01-core.nix` — falsch (Ports in `08-ports.nix`)

**Abhängigkeiten:** —

**Empfehlung:** refactor needed — README an aktuelle Dateistruktur anpassen

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| Port-SSoT | ⚠ | `08-ports.nix` ist gut, aber 5+ Dienste umgehen die Registry |
| UID-SSoT | ✓ | Partielle Registry, Duplikat-Guard funktioniert |
| Secrets | ✓ | systemd-creds-Strategie konsistent, sops verboten |
| IPv6 | ✓ | Optionen vorhanden, Homelab v4-only ist Designentscheidung |
| Cross-Layer | ⚠ | `04-services-spec` → `my.ingress` (10-network), `06-boot-watchdog` → Linkwarden/Caddy |
| Dokumentation | ✗ | README driftet stark vom Code ab |

## Priorisierte Empfehlungen

1. **README.md aktualisieren** — falsche Dateinamen, falsche Zweckbeschreibungen
2. **Boot-Generation-Limit konsolidieren** — `rollout.nix` mkForce vs. `boot-safeguard.configurationLimit`
3. **`my.ports.home-assistant = 8123`** in `08-ports.nix` + Spec-Anbindung
4. **Boot-Watchdog entkoppeln** — Restart-Policies/Requires in Domänenmodule verschieben
5. **Fehlende Ports** in Registry ergänzen (Wyoming, Hermes, node-exporter) — oder bewusst als „non-ingress" dokumentieren