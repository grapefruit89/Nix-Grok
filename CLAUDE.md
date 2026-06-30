# CLAUDE.md — q958 NixOS Server: lies dies ZUERST, in jeder Session

## Regel 0 — Verifizieren, nicht erinnern

Jede aus dem Memory erinnerte Zusammenfassung einer früheren Session ist
**niemals aktuelle Wahrheit** — nur ein Hinweis, was zu prüfen ist. Bevor
du irgendeine Annahme über den Systemzustand triffst oder einen Plan
vorschlägst, führe IMMER zuerst aus:

```bash
git -C /etc/nixos log --oneline -10
git -C /etc/nixos status --short
systemctl list-units --type=service --state=running --no-pager | head -40
systemctl --failed --no-pager
nixos-version
cat /etc/nixos/machines/q958/rollout.nix | grep -n 'stufe ='
```

Wenn eine alte Memory etwas anderes behauptet als das, was diese Befehle
gerade zeigen — die Befehle haben recht, nicht die Memory. Sag das dem
Menschen explizit, wenn du eine Diskrepanz findest, bevor du weitermachst.

Lies danach `AGENTS.md` im Repo-Root — das ist die verbindliche
Architektur-Verfassung (6-Schichten-Modell, Nummerierungsschema,
NIXMETA-Verbot, harte Regeln). Dieses Dokument hier ist die
Tages-aktuelle Briefing-Ergänzung dazu, kein Ersatz.

## Philosophie: Nix-Native Pragmatic Declarative

Entscheidungsreihenfolge für jede Änderung am Stack:

1. **Nix-Native first** — `services.*`, Optionen, Env-Vars, systemd nutzen bevor Code gebaut wird
2. **Declarative Core** — gewünschter Zustand in Nix definiert, nicht nur dokumentiert
3. **Surgical Glue** — eigener Code nur wo Nix nicht hinreicht (Sync-Service, Secrets-Provision)
4. **Minimal Abstraction** — Factory stärken, nicht ersetzen; kein Over-Engineering
5. **Transparent & Wartbar** — lesbar in 2 Jahren, keine magischen Module

Kurzform: *„Declarative Core + Surgical Glue"*

## Schreibzugriff auf /etc/nixos

`/etc/nixos` gehört nach dem Benutzer-Refactor (2026-06-28) **root**.
Claude Codes native Edit/Write-Tools haben kein sudo — direkte Schreibversuche
enden mit "Permission denied".

**Das richtige Muster für jede Dateiänderung:**

```bash
# 1. Original-Mode prüfen
sudo ls -la /etc/nixos/pfad/zur/datei

# 2. Neue Version in den Session-Scratchpad schreiben (Write-Tool oder Bash)
#    Scratchpad-Pfad steht im System-Prompt der Session, z.B.:
#    /tmp/claude-<uid>/-home-moritz/<session-id>/scratchpad/

# 3. Mit sudo install an den Zielpfad kopieren:
sudo install -o root -g root -m <original-mode> <scratchpad-datei> /etc/nixos/pfad/zur/datei
```

**⚠ Warnung: `-m <mode>` immer explizit angeben!**
`sudo install` ohne `-m` setzt den Mode auf den System-Default — nicht auf
den Originalwert. Typischer Bug: ein Script mit Mode 755 (ausführbar) wird
nach `install` ohne `-m` zu 644 und scheitert beim Ausführen. Vor jedem
`install` erst `sudo ls -la <zielpfad>` ausführen und den Mode übernehmen.

**Ausnahme:** Edit-Tool funktioniert direkt für Dateien in Unterordnern
(z. B. `modules/50-media/`, `modules/20-security/`). Nur Dateien im
Root von `/etc/nixos/` (wie `CLAUDE.md`, `flake.nix`) brauchen sudo install.

## Rebuild-Workflow — Dry-Run-Gate (Pflicht)

**Niemals** `nixos-rebuild switch` direkt ausführen. Immer zuerst:

```bash
# 1. Dry-Build verifizieren (läuft auch als Claude-Schritt):
sudo scripts/nixos-rebuild-safe.sh

# 2. Erst wenn "✓ Dry-build erfolgreich" erscheint, switch ausführen.
#    Empfehlung: in tmux (SSH-sicher, überlebt Verbindungsabbrüche):
tmux new-session 'sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure 2>&1 | tee /tmp/nixos-switch.log; echo "Exit: $?"; read'
```

Warum tmux: `nixos-rebuild switch` starb bisher mit exit 137 (SIGKILL) bei
SSH-Disconnect, weil der Terminal-Prozessgraph den SIGHUP weiterleitet.
tmux entkoppelt den Build-Prozess vom SSH-Terminal.

Das Script `scripts/nixos-rebuild-safe.sh check` prüft, ob für den
aktuellen HEAD ein Dry-Build-Flag gesetzt ist — nützlich als Voraussetzung.

## Was JETZT Stand ist (Stand: 2026-06-28, nach Benutzer-Refactor)

- `/etc/nixos` **existiert**, ist ein Git-Repo (`origin` = `github.com/grapefruit89/Nix-Grok`).
  Owner ist nach dem Post-Switch-Migration-Schritt **root** (vorher: `nixos`-User).
  Zugriff auf Dateien dort nur via `sudo install -o root -g root ...`.
- **SSH-User ist `admin`** (nach nixos-rebuild switch + manuellem `usermod`).
  Konfiguriert in `users/admin/profile.nix` → nur dort `name` ändern für Umbenennung.
  Kein Emergency-User (`nixos`) mehr — Konsolen-Fallback ist root-Autologin auf tty1.
- **GitHub Deploy-Key** nach Migration: `/root/.ssh/id_ed25519_github` (war: `/home/nixos/.ssh/`).
- **Aktiv und laufend:** Jellyfin, Sonarr/Radarr/Readarr/Prowlarr/Lidarr (über
  `modules/50-media/arr.nix`, eine gemeinsame Fabrik), SABnzbd, Vaultwarden,
  PostgreSQL, Grafana/Loki/Gatus, Caddy, CrowdSec, Hermes-Agent (nativ,
  NVIDIA-Provider), Claude Code CLI (Paket installiert), Home Assistant,
  Zigbee2MQTT, n8n, Forgejo, Semaphore, AMP — die meisten über
  `rollout.stufe`-Gating (`erstAb N`).
- **Bewusst deaktiviert:** Grok (CLI + Module), Gemini-Reste — beide
  archiviert unter `/home/admin/.archive-2026-06-25/` (nach usermod-Migration).
- `rollout.stufe = 8` (Development-Rail). **Bleibt vorerst so** — Impermanence,
  SOPS und Production-Hardening sind bewusst nach hinten verschoben, bis die
  Config fertig und fehlerfrei ist (explizite Entscheidung vom Menschen).
- Root: nur via physische TTY-Konsole, Autologin, kein Passwort.
  SSH: nur `admin`, nur SSH-Key, **kein Passwort, nirgendwo, niemals**.
- **Unified Port=UID=FolderPrefix Schema** implementiert (ADR-011):
  ID = Port = UID = Ordner-Präfix (4-stellig). Quellen: `lib/uid-registry.nix`,
  `lib/server-map.nix`, `modules/00-core/01-core.nix`.
- **NixOS-Docs MCP** (`scripts/nixos-docs-mcp.py`): FTS5 + sqlite-vec +
  Hybrid-RRF-Suche auf `data/nixos_docs.sqlite`. Nach rebuild aktivieren
  und in `modules/mcp-server/default.nix` eintragen.

## Dev-System-Philosophie — maximal progressiv

q958 ist eine Dev-Maschine ohne echte Nutzerdaten. Keinerlei Rücksicht auf
alte `/var/lib/*`-Daten nötig. Wenn ein Wipe schneller zum Ziel führt: sofort
wischen, kein Backup, keine Rückfrage. Ausnahmen: `/data/media`, `/etc/nixos`.

## Aktive TODOs — Stand 2026-06-30

**UMGESETZT (diese Session):**
- [x] arr-helper.nix: `readOnlyPaths=["/data/media"]` → ReadWritePaths verschoben
- [x] arr-helper.nix + arr.nix: `AUTH__METHOD=External`, `LOG__LEVEL=info`, `UPDATE__BRANCH` per App
- [x] sabnzbd.nix: `SABNZBD__MISC__TEMP_DIR=/run/sabnzbd-tmp`
- [x] jellyfin-system.xml: TrickplayOptions, GroupingShows, DisplaySpecials
- [x] Caddy crash-loop: `ip_mask /24` → `ip_mask 24` in 11-network.nix (**Switch ausstehend**)
- [x] Jellyfin crash-loop: preStart CAP_CHOWN → systemd.tmpfiles.rules (**Switch ausstehend**)
- [x] arr-helper.nix: tmpfiles.rules für metadataDir + MediaCover (fresh-install-safe)
- [x] lidarr.env + readarr.env erstellt + /mnt/fast_pool/metadata/lidarr → lidarr läuft
- [x] Home Assistant: komplett gewischt + frisch gestartet (v2026.5.4)

**OFFEN — HOCH (Switch blockiert):**
- [ ] **nixos-rebuild switch** — aktiviert Caddy-Fix + Jellyfin-Fix:
  `tmux new-session 'sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure 2>&1 | tee /tmp/nixos-switch.log; echo "Exit: $?"; read'`
- [ ] *arr-UID-Migration: `scripts/migrate-arr-uids.sh` einmalig nach Switch

**OFFEN — MONITORING (neue Feature-Gruppe, in dieser Reihenfolge abarbeiten):**
- [ ] **1. vmalert + ntfy**: `services.vmalert.instances.q958` + `services.prometheus.alertmanager-ntfy`
  in `44-metrics.nix` / `05-alerting.nix`. Regeln: service_failed, high_restarts.
  User trägt in `profile.local.nix` ein: `my.alerting.ntfyTopic = "q958-alerts";`
- [ ] **2. process_exporter**: `services.prometheus.exporters.process` (Port 9256),
  Scrape in VictoriaMetrics, Gruppen nach systemd-Unit-Namen → CPU/RAM pro Service.
- [ ] **3. Alert-Script mit AI**: Shell-Script: journalctl-Log → Groq API
  (Modell: llama-3.1-8b-instant, kostenlos auf groq.com) → ntfy ans Handy.
  Optional: Gemini als Fallback. Secret: `/var/lib/secrets/groq.env`.
- [ ] **4. Runbook** (`docs/RUNBOOK.md`): Markdown mit `error_pattern`-Feld im
  Frontmatter, `quick_fix`-Befehlen, Sektions-Ankern. Alert-Script matcht
  Fehler via `grep error_pattern` und schickt Abschnitt an AI.

**OFFEN — NIEDRIG:**
- [ ] recyclarr: `services.recyclarr.*` NixOS-Modul (8.5.1 in nixpkgs)
- [ ] NixOS-Docs MCP noch nicht in `modules/mcp-server/default.nix` verdrahtet
- [ ] ADRs 014–018: Guide-Links im Frontmatter nachtragen
- [ ] ADRs: `error_pattern`-Feld für maschinenlesbare Fehler-Erkennung

## Bekannte offene Baustellen (nicht überraschend, nicht von dir verursacht)

- **scrutiny.service**: crash-loopt seit Wochen, braucht eine InfluxDB-Instanz
  auf Port 8089, die nie aufgesetzt wurde. Nicht dringend.
- **sabnzbd**: Newshosting-Server-Eintrag hat noch Platzhalter-Credentials
  (`placeholder_user`/`placeholder_pass`) — Downloads laufen nicht, bis der
  Mensch echte Zugangsdaten im Webinterface einträgt.
- **media-stack-config-sync.service**: Prowlarr-API-Sync wird übersprungen
  solange `privado-vpn.service` inaktiv ist (kein WireGuard-Key in
  `profile.local.nix` eingetragen — bewusst offen). Locale-Sync (Jellyfin,
  SABnzbd) läuft durch. Service endet mit exit 0.
- **Architektur-Migration** (`modules/` → strikt flache `00`–`90`-Ordner
  mit `NNss`-Dateinamen, `machines/` → `hosts/`) ist **in Arbeit** —
  `00-core/` und `10-network/` sind fertig, restliche Domänen folgen.
- **python3 fehlt im System-PATH** — der NIXMETA-Pre-Commit-Hook in
  `.git/hooks/pre-commit` prüft am Anfang, ob `python3` verfügbar ist, und
  überspringt sich selbst still, wenn nicht. Solange Python nicht im
  `environment.systemPackages` steht, hat der Hook keine Wirkung.
- **stage-nixos/ im Repo-Root**: Verzeichnis mit veralteten Staging-Dateien,
  gitignored (also kein Versionsschutz). Kandidat für Verschiebung nach
  `/home/moritz/.archive-2026-06-25/stage-nixos/` — aber erst prüfen, ob
  der Mensch es noch als Referenz braucht. Nicht von selbst löschen.
- **Tote Grok-Reste im Repo**: `modules/60-apps/grok.nix`,
  `packages/grok-cli/`, Flake-Wiring in `flake.nix`, Block in
  `users/moritz/home.nix` — alles deaktiviert aber noch vorhanden.
  Aufräumen sobald der Mensch grünes Licht gibt.
- **NixOS-Docs MCP** noch nicht in `modules/mcp-server/default.nix` verdrahtet
  — `scripts/nixos-docs-mcp.py` existiert, braucht noch systemd-Service-Definition.
- ***arr-UID-Migration** noch ausstehend: `scripts/migrate-arr-uids.sh` einmalig
  nach dem nächsten switch ausführen (chown auf `/persist/var/lib/{sonarr,...}`).

## MCP-Tools — PFLICHT bei Paket- und Optionsfragen

> **PFLICHT-ERINNERUNG — Immer bevor du einen Namen nennst oder Code schreibst:**
> - Paketnamen / `services.*`-Option / NixOS-Modul → **nixos-MCP** (nie aus Training annehmen!)
> - `lib.*`-Funktion / `builtins.*` → **Noogle** (Argumente-Reihenfolge ändert sich zwischen Versionen!)
> - Caddy, Jellyfin-API, systemd-Optionen, externe Bibliotheken → **Context7**
>
> Keine Ausnahmen. „Ich weiß das aus Training" ist kein gültiger Grund. Falsche
> Annahmen aus Training kosten mehr Zeit als ein MCP-Call.

Trainingsdaten sind bis zu 18 Monate alt. Für Live-Daten IMMER die MCP-Server nutzen
**bevor** du eine Annahme über nixpkgs-Pakete, NixOS-Optionen, Caddy-Direktiven, etc. triffst.

### nixos-MCP (nixpkgs live-Suche)
Nutze `mcp__nixos__nix` für:
- Paket-Existenz prüfen: `{"action":"info","query":"<pkg>","channel":"nixos-unstable"}`
- NixOS-Optionen durchsuchen: `{"action":"search","query":"<option>","type":"options"}`
- Home-Manager-Optionen: `{"action":"search","source":"home-manager","query":"<option>"}`
- Binary-Cache-Check: `{"action":"cache","query":"<pkg>"}`
- **Noogle** (Nix builtins + lib.\*): `{"action":"search","source":"noogle","query":"lib.mapAttrs"}`
- **nix.dev Docs**: `{"action":"search","source":"nix-dev","query":"flake inputs"}`

Wann: **Immer**, wenn du ein NixOS-Modul, ein `services.*`-Attribut oder einen
Paket-Namen nennst, den du nicht in den letzten 5 Minuten live verifiziert hast.
"Ich weiß das aus Training" reicht nicht — `fetchurl`-Hashes, Plugin-Versionen,
Moduloptionen ändern sich ständig.

### Noogle — PFLICHT bei lib.\*-Funktionen und Nix-Builtins
Noogle indexiert alle Nix-Standardbibliotheksfunktionen mit Signaturen, Beschreibungen
und Beispielen. **Immer verwenden** bevor du eine `lib.*`-Funktion aus dem Gedächtnis
anwendest oder über `builtins.*` spekulierst:

```
# Funktion suchen
mcp__nixos__nix  {"action":"search","source":"noogle","query":"lib.mapAttrs"}
mcp__nixos__nix  {"action":"search","source":"noogle","query":"lib.strings.concatMapStrings"}
mcp__nixos__nix  {"action":"search","source":"noogle","query":"builtins.readFile"}

# Namespace durchstöbern
mcp__nixos__nix  {"action":"browse","source":"noogle","query":"lib.attrsets"}
```

**Human-CLI**: `noogle-search` (interaktiv mit fzf) oder Alias `noogle`.
**Wann**: Jedes Mal wenn du eine `lib.*`-Funktion schreibst, die du nicht gerade
live verifiziert hast — Argumente-Reihenfolge, Lazy vs. Strict, Edge-Cases ändern
sich zwischen nixpkgs-Generationen.

### Context7-MCP (Bibliotheks-Dokumentation)
Nutze `mcp__claude_ai_Context7__resolve-library-id` + `query-docs` für:
- Caddy-Direktiven und -Konfiguration
- systemd-Unit-Optionen
- Jellyfin/Navidrome/Audiobookshelf API-Details
- NixOS-Flake-Struktur und -API
- Jede Bibliothek, über die du nicht 100% sicher bist

Ablauf: erst `resolve-library-id` mit dem Library-Namen, dann `query-docs` mit
der Library-ID und der spezifischen Frage.

## Moderne CLI-Tools — Pflicht im interaktiven Betrieb

Folgende moderne Tools sind systemweit installiert und **müssen bevorzugt werden**:

| Deprecated    | Modernes Äquivalent               | Hinweis |
|---------------|-----------------------------------|---------|
| `cat`         | `bat --paging=never`              | Alias gesetzt |
| `ls`          | `eza --icons --git`               | Alias gesetzt; `ll` = mit `-la` |
| `find`        | `fd`                              | Alias gesetzt |
| `grep`        | `rg` (ripgrep)                    | Alias gesetzt |
| `du`          | `dust`                            | Alias gesetzt |
| `df`          | `duf`                             | Alias gesetzt |
| `nix build` (Output) | `nom` (nix-output-monitor)  | `nom build .#q958` |
| Dep-Graph manuell | `nix-tree /nix/store/<drv>` | Visualisiert Abhängigkeiten |
| Store-Vergleich | `nix-diff old new`            | Diff zweier Store-Paths |
| Nix-Funktion googeln | `noogle` / `noogle-search` | Interaktive fzf-Suche |
| `top`         | `btop`                            | Alias gesetzt |
| `nixos-rebuild switch` | `nh os switch --flake /etc/nixos#q958` | Nur für menschliche Rebuilds; **Dry-Build-Gate bleibt `sudo scripts/nixos-rebuild-safe.sh`** |

**Für Claude Code:** Das Claude-Code-System-Prompt verbietet `cat`/`head`/`tail`/`sed`/`awk`
bereits — stattdessen `Read`/`Edit`/`Write`-Tools nutzen. Die Shell-Aliases greifen nur für
interaktive Bash-Sitzungen, nicht für Bash-Tools-Aufrufe durch Claude Code.

**Nach einem `nixos-rebuild switch`** immer `nvd` ausführen, um den Diff anzuzeigen.

## Harte Grenzen — gelten für JEDEN Agenten hier, ausnahmslos

1. **`nixos-rebuild switch` führt nur der Mensch aus** — niemals automatisch,
   auch nicht nach erfolgreichem Dry-Build, auch nicht auf Zuruf.
   Vorher immer: `sudo scripts/nixos-rebuild-safe.sh` (Dry-Run-Gate).
2. **`git push` nur nach expliziter, klarer Zustimmung im Chat** — nicht
   vorher einfach annehmen.
3. Secrets niemals in Git. `machines/q958/profile.local.nix` ist gitignored.
4. NIXMETA (`# !type`-Annotationen) ist permanent verboten — siehe
   `modules/00-nixmeta-ban.nix` und `tools/validate_headers.py`.
5. Vor jedem Commit: `sudo scripts/nixos-rebuild-safe.sh` (dry-build) muss
   grün sein. Kein Flag gesetzt → kein Commit.

## Git-Historie, falls relevant

`master`/`main` wurden heute neu aufgesetzt (alter Stand war ein Wurzel-Commit
ohne Verbindung zur 112-Commit-Historie unter dem alten `main`). Diese ältere
Historie ist nicht verloren, nur nicht mehr die Spitze von `main`. Wenn du
nach "der alten Version von X" suchst und sie nicht findest: `git log --all`
und `git reflog` durchsuchen, bevor du sagst, dass es sie nicht gibt.
