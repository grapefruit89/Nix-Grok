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

Nach jeder Änderung: `sudo nixos-rebuild dry-build --impure` muss grün
sein, bevor committed wird.

## Was JETZT Stand ist (Stand: 2026-06-26, nach dem ersten Switch)

- `/etc/nixos` **existiert**, ist ein Git-Repo (`origin` = `github.com/grapefruit89/Nix-Grok`),
  Owner ist der User `nixos` (nicht `moritz`, nicht `root`) — Zugriff auf
  Dateien dort nur via `sudo`.
- Heute zum ersten Mal seit Wochen erfolgreich `nixos-rebuild switch --impure`
  gefahren. Läuft jetzt auf Generation, gebaut aus dem aktuellen `main`.
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
- **Doppelte `hermes-agent.enable`-Zeile**: `services.hermes-agent.enable = true`
  steht sowohl in `machines/q958/default.nix` als auch in
  `machines/q958/rollout.nix`. Laut Regel: enable-Flags gehören nur in
  `rollout.nix`. Zeile in `default.nix` ist redundant und kann entfernt
  werden.

## Harte Grenzen — gelten für JEDEN Agenten hier, ausnahmslos

1. **`nixos-rebuild switch` führt nur der Mensch aus.** Niemals automatisch,
   auch nicht nach erfolgreichem Dry-Build, auch nicht auf Zuruf.
2. **`git push` nur nach expliziter, klarer Zustimmung im Chat** — nicht
   vorher einfach annehmen.
3. Secrets niemals in Git. `machines/q958/profile.local.nix` ist gitignored.
4. NIXMETA (`# !type`-Annotationen) ist permanent verboten — siehe
   `modules/00-nixmeta-ban.nix` und `tools/validate_headers.py`.
5. Vor jeder Änderung: `nixos-rebuild dry-build --impure` muss grün sein,
   bevor irgendetwas committed wird.

## Git-Historie, falls relevant

`master`/`main` wurden heute neu aufgesetzt (alter Stand war ein Wurzel-Commit
ohne Verbindung zur 112-Commit-Historie unter dem alten `main`). Diese ältere
Historie ist nicht verloren, nur nicht mehr die Spitze von `main`. Wenn du
nach "der alten Version von X" suchst und sie nicht findest: `git log --all`
und `git reflog` durchsuchen, bevor du sagst, dass es sie nicht gibt.
