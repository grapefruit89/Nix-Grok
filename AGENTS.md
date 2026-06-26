---
meta:
  role: doc
  purpose: Projektregeln — 6-Schichten-Architektur, q958, Rollout, harte Regeln
  docs:
    - docs/FILE-META.md
    - modules/_HEADER_TEMPLATE.nix
  tags:
    - agents
    - architecture
---

# Projektregeln — /etc/nixos

## Architektur (6 Schichten)

| # | Pfad | Rolle |
|---|---|---|
| 1 | `flake.nix` | Einstieg, Inputs, Outputs |
| 2 | `hosts/<host>/` | Maschine — Hardware, Netzwerk, Rollout |
| 3 | `users/<name>/` | Person — Keys, Domain, Home-Manager |
| 4 | `modules/` + `packages/` | Generische Fähigkeiten — leere/neutrale Defaults |
| 5 | `mcp/` | Modell-unabhängige MCP-Server-Definitionen — von jedem KI-Tool nutzbar |
| 6 | `lib/` | Gemeinsame Helfer — `secrets/` kommt ganz zum Schluss, nie committed |

(Hinweis: `hosts/` heißt im Code aktuell noch `machines/` — Umbenennung ist
geplant, aber noch nicht physisch durchgeführt. Bis dahin gilt `machines/`
als Synonym für Schicht 2.)

## Modules-Struktur — strikt flach, zweistufig nummeriert

`modules/` selbst enthält **keine** `.nix`-Dateien — nur genau 10 Ordner,
in Zehnerschritten:

```
00-core/  10-network/  20-security/  30-storage/  40-observability/
50-media/ 60-apps/     70-forge/     80-gaming/    90-policy/
```

Innerhalb eines Ordners: **keine weiteren Unterordner**. Einzige Ausnahme:
`data/` für statische Nicht-Nix-Assets (z.B. XML-Templates) — das zählt
nicht als "Modul" und ist vom Verbot nicht betroffen.

### Datei-Nummerierung innerhalb eines Ordners

Jede Datei in `NN-wort/` heißt `NNss-name.nix`, wobei:

- `NN` = die Ordner-Domäne (00, 10, 20 … 90 — identisch zum Ordnernamen)
- `ss` = Position/Wichtigkeit **innerhalb** der Domäne, ebenfalls in
  Zehnerschritten (00, 10, 20 … 90)

Beispiel für `modules/50-media/`:

```
5010-jellyfin.nix
5020-sonarr.nix      (zweiter Dienst der Domäne)
5030-radarr.nix
5040-readarr.nix
5050-prowlarr.nix
```

Die Zehnerschritte lassen Luft zum Einschieben (z.B. `5015` für einen neuen
Dienst zwischen Jellyfin und Sonarr), ohne den ganzen Ordner umzunummerieren.

**Ausnahme (explizit erlaubt):** stark verwandte Dienste dürfen sich eine
Datei + eine Fabrik teilen, wenn das Code spart — z.B. der *arr-Stack
(`50-media/arr.nix`, ohne eigene Nummer im Dateinamen, da Mehrfach-Datei).
Die einzelnen Dienste **behalten trotzdem** ihre eigene UID/Port-Nummer
(siehe Isomorphie unten).

### Isomorphie: UID === Nummer === Port

Wo technisch sinnvoll, ist die 4-stellige `NNss`-Nummer gleichzeitig:

- der Datei-Präfix
- die System-UID des Service-Users (`config.my.users.registry.<name>`)
- der TCP/UDP-Port (`config.my.ports.<name>`)

Beispiel: Sonarr in `50-media/`, zweiter Dienst → Nummer `5020` →
UID `5020`, Port `5020`. Vier Stellen reichen aus (Ports gehen nur bis
65535; 9 Domänen × 9 Slots × 4-stellig ist genug Raum und bleibt lesbar —
5-stellig wäre zu nah an der Port-Obergrenze und unnötig sperrig).

**Migrationshinweis:** Bestehende Services haben aktuell noch ihre alten,
teils konventionellen Ports/UIDs (z.B. Sonarr=8989). Eine Umstellung auf
das neue Schema ist eine **eigene, bewusste Migration** (Portänderung +
rekursives `chown` bestehender `/var/lib/<service>`-Daten) — wird **nicht**
einfach nebenbei beim Verschieben einer Datei mitgemacht, da das laufende
Dienste/Bookmarks/Reverse-Proxy-Ziele brechen kann. Neue Services ab sofort
nach diesem Schema, alte Services schrittweise und einzeln nachziehen.

## Trennung pro Host (`machines/<host>/`)

| Datei | Was gehört rein |
|---|---|
| `profile.nix` | IP, Hardware, Storage, Kernel, `rollout.stufe` — **nur Daten** |
| `default.nix` | Imports, `my.configs` — **reine Verdrahtung, keine `.enable`** |
| `access.nix` | Stufe 0+: Zugang (Netzwerk, Notfall-User, Assertions) |
| `rollout.nix` | Service-Aktivierung nach `rollout.stufe` — **einzige `.enable`-Quelle** |
| `hardware.nix` | `fileSystems`, Kernel-Module (liest `profile.nix`) |
| `profile.local.nix` | Gitignored. Echte Secrets/Overrides — niemals committen |

## Trennung pro User (`users/<name>/`)

| Datei | Was gehört rein |
|---|---|
| `profile.nix` | SSH-Keys, Domain, Gruppen, Shell — personenbezogen |
| `default.nix` | System-User-Definition (liest `profile.nix`) |
| `home.nix` | Home-Manager / Dotfiles |

## `mcp/` — Schicht 5

- Eine Datei pro MCP-Server: `mcp/<name>.nix`
- `options.my.mcp.<name>.enable` pro Server
- `mcp/default.nix` aggregiert alle
- Modellunabhängig: wird von Claude Code, Hermes etc. referenziert, nicht umgekehrt

## NIXMETA — permanent verboten

Das alte `# !type`-Annotationsformat ist seit 2026-06-26 **absolut verboten,
keine Ausnahmen**. Durchsetzung zweistufig:

1. `tools/validate_headers.py` als Git-Pre-Commit-Hook (schnelles Feedback
   beim Commit — benötigt `pkgs.python3` im System, sonst No-Op mit Warnung)
2. `modules/00-nixmeta-ban.nix` — echte Nix-Build-Assertion, scannt den
   ganzen Baum über `builtins.readFile` zur Build-Zeit. Schlägt auch fehl,
   wenn der Hook umgangen wurde — das ist die eigentliche Durchsetzung.

## YAML-Header — verbindlich für jede `.nix`-Datei

Leer-Vorlage zum Kopieren: `modules/_HEADER_TEMPLATE.nix` — alle
wiederkehrenden Werte (Service-Name, Domäne, Nummer) sind dort als
Variablen im `let`-Block deklariert, damit eine KI nicht jedes Mal neu
überlegen muss, wo was hingehört.

Schema:

```nix
# ---
# id: "service-name"
# domain: "50"          # 00|10|20|30|40|50|60|70|80|90
# status: "active"      # proposed | active | deprecated | template
# layer: 4              # 1-6, siehe Architektur-Tabelle oben
# purpose: "Kurzbeschreibung in einem Satz"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: []
# ---
```

Echtes YAML, Obsidian-kompatibel, maschinenlesbar — keine `!type`/`!enum`-
Sonderannotationen (das wäre NIXMETA und damit verboten).

## Die 8 Refaktor-Regeln (modules/, Stand 2026-06-26)

1. **Weg vom Monolithen** — ein Ordner pro Domäne, keine 1000-Zeilen-Dateien.
2. **YAML-Metadatenheader** auf jeder Datei (siehe oben).
3. **Eine Datei pro Funktion/Anwendung** — Ausnahme: *arr-Stack (s.o.).
4. **Keine `.nix`-Dateien direkt in `/modules/`** — nur in den 10 Domänen-Ordnern.
5. **Obergrenze ~500 Zeilen** pro Datei — Überschreiten nur mit expliziter Begründung im Header.
   `lib/service-factory.nix` und `lib/services-spec.nix` dürfen länger sein,
   wenn künstliches Aufteilen die Lesbarkeit verschlechtern würde.
6. **Bevorzugt nix-pkgs** statt Adhoc-Binaries/Skripte. Ausnahme: generisches
   Tooling (`tools/*.py`, `tools/*.sh` für DB-Sync, ATLAS-Generator etc.)
   ist kein "Paket" im eigentlichen Sinn — zählt nicht als Verstoß.
7. **Docker ist verboten**, keine Ausnahmen.
8. **Podman ist zähneknirschend erlaubt** — aber nur, wenn kein natives
   nix-pkg existiert. Prüfung zuerst, Container erst als letzter Ausweg.
   Beispiel: Hermes-Agent läuft seit 2026-06-26 nativ (vorher Podman),
   weil ein natives Paket verfügbar war.

## Harte Regeln

1. Kein Service-`.enable` außerhalb von `machines/<host>/rollout.nix`.
2. Keine Secrets in Git — `profile.local.nix` ist gitignored, niemals
   `git add -f`. Container-Runtime-State, Chat-Historys, `.bak`-Dateien
   gehören nie ins Repo (siehe `.gitignore`).
3. Ein Commit = eine logische Änderung. Vor jedem Push: `git diff` selbst
   gegenlesen, damit nichts versehentlich mitgenommen wird.
4. Neue Services: `modules/60-apps/SERVICE_TEMPLATE.nix` bzw.
   `modules/_HEADER_TEMPLATE.nix` kopieren, anpassen, Fabrik
   (`lib/service-factory.nix`) nutzen statt eigenes systemd-Hardening
   zu schreiben.
5. Vor jedem Push: `nixos-rebuild dry-build --impure` muss grün sein.
6. Hygiene-Trio (`statix → deadnix → nixfmt`) läuft regelmäßig, nie
   ungeprüft, niemals automatisch gefolgt von einem Push.
7. **`nixos-rebuild switch` und `git push` sind ausschließlich
   menschliche Aktionen.** Eine KI führt beides nie selbst aus — auch
   nicht nach erfolgreichem Dry-Build, auch nicht auf expliziten Wunsch.
   Lokale Commits sind dagegen erlaubt (nach erfolgreicher Validierung).
8. Root ist nur über die physische TTY-Konsole erreichbar (Autologin,
   kein Passwort). SSH ist ausschließlich für `moritz`, ausschließlich
   per Key — kein Passwort, nirgendwo, niemals.
