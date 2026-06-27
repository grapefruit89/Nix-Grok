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

## Schreibzugriff auf /etc/nixos

`/etc/nixos` gehört dem User `nixos`. Claude Codes native Edit/Write-Tools
haben kein sudo — direkte Schreibversuche enden mit "Permission denied".

**Das richtige Muster für jede Dateiänderung:**

```bash
# 1. Original-Mode prüfen
sudo ls -la /etc/nixos/pfad/zur/datei

# 2. Neue Version in den Session-Scratchpad schreiben (Write-Tool oder Bash)
#    Scratchpad-Pfad steht im System-Prompt der Session, z.B.:
#    /tmp/claude-<uid>/-home-moritz/<session-id>/scratchpad/

# 3. Mit sudo install an den Zielpfad kopieren:
sudo install -o nixos -g users -m <original-mode> <scratchpad-datei> /etc/nixos/pfad/zur/datei
```

**⚠ Warnung: `-m <mode>` immer explizit angeben!**
`sudo install` ohne `-m` setzt den Mode auf den System-Default — nicht auf
den Originalwert. Typischer Bug: ein Script mit Mode 755 (ausführbar) wird
nach `install` ohne `-m` zu 644 und scheitert beim Ausführen. Vor jedem
`install` erst `sudo ls -la <zielpfad>` ausführen und den Mode übernehmen.

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

## Was JETZT Stand ist (Stand: 2026-06-27, nach Unified-Port-UID-Migration)

- `/etc/nixos` **existiert**, ist ein Git-Repo (`origin` = `github.com/grapefruit89/Nix-Grok`),
  Owner ist der User `nixos` (nicht `moritz`, nicht `root`) — Zugriff auf
  Dateien dort nur via `sudo`.
- **Aktiv und laufend:** Jellyfin, Sonarr/Radarr/Readarr/Prowlarr (über
  `modules/50-media/arr.nix`, eine gemeinsame Fabrik), SABnzbd, Vaultwarden,
  PostgreSQL, Grafana/Loki/Gatus, Caddy, CrowdSec, Hermes-Agent (nativ,
  NVIDIA-Provider), Claude Code CLI (Paket installiert), Home Assistant,
  Zigbee2MQTT, n8n, Forgejo, Semaphore, AMP — die meisten über
  `rollout.stufe`-Gating (`erstAb N`).
- **Bewusst deaktiviert:** Grok (CLI + Module), Gemini-Reste — beide
  archiviert unter `/home/moritz/.archive-2026-06-25/`, nicht gelöscht.
- `rollout.stufe = 8` (Development-Rail). **Bleibt vorerst so** — Impermanence,
  SOPS und Production-Hardening sind bewusst nach hinten verschoben, bis die
  Config fertig und fehlerfrei ist (explizite Entscheidung vom Menschen).
- Root: nur via physische TTY-Konsole, Autologin, kein Passwort.
  SSH: nur `moritz`, nur SSH-Key, **kein Passwort, nirgendwo, niemals**
  (auch nicht im Dev-Rail — das wurde heute bewusst von der alten
  "Rail 1 Never-Lockout"-Philosophie abgewichen).
- Der `nixos`-Emergency-User hat kein Passwort mehr, existiert aber noch
  als Account (Löschen steht noch aus — braucht erst einen Ownership-Umzug
  von `/etc/nixos`, weg vom `nixos`-User).
- **Unified Port=UID=FolderPrefix Schema** implementiert (ADR-011):
  ID = Port = UID = Ordner-Präfix (4-stellig). Quellen: `lib/uid-registry.nix`,
  `lib/server-map.nix`, `modules/00-core/01-core.nix`.
- **NixOS-Docs MCP** (`scripts/nixos-docs-mcp.py`): FTS5 + sqlite-vec +
  Hybrid-RRF-Suche auf `data/nixos_docs.sqlite`. Nach rebuild aktivieren
  und in `modules/mcp-server/default.nix` eintragen.

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

Trainingsdaten sind bis zu 18 Monate alt. Für Live-Daten IMMER die MCP-Server nutzen
**bevor** du eine Annahme über nixpkgs-Pakete, NixOS-Optionen, Caddy-Direktiven, etc. triffst.

### nixos-MCP (nixpkgs live-Suche)
Nutze `mcp__nixos__nix` für:
- Paket-Existenz prüfen: `{"action":"info","query":"<pkg>","channel":"nixos-unstable"}`
- NixOS-Optionen durchsuchen: `{"action":"search","query":"<option>","type":"options"}`
- Home-Manager-Optionen: `{"action":"search","source":"home-manager","query":"<option>"}`
- Binary-Cache-Check: `{"action":"cache","query":"<pkg>"}`

Wann: **Immer**, wenn du ein NixOS-Modul, ein `services.*`-Attribut oder einen
Paket-Namen nennst, den du nicht in den letzten 5 Minuten live verifiziert hast.
"Ich weiß das aus Training" reicht nicht — `fetchurl`-Hashes, Plugin-Versionen,
Moduloptionen ändern sich ständig.

### Context7-MCP (Bibliotheks-Dokumentation)
Nutze `mcp__claude_ai_Context7__resolve-library-id` + `query-docs` für:
- Caddy-Direktiven und -Konfiguration
- systemd-Unit-Optionen
- Jellyfin/Navidrome/Audiobookshelf API-Details
- NixOS-Flake-Struktur und -API
- Jede Bibliothek, über die du nicht 100% sicher bist

Ablauf: erst `resolve-library-id` mit dem Library-Namen, dann `query-docs` mit
der Library-ID und der spezifischen Frage.

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
