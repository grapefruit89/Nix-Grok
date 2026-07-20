# ⛔ STILLGELEGT — dieser Ordner ist nicht mehr die Wahrheit

**Seit:** 2026-07-20

## Kurz

Der Medienstack wird ab sofort **eigenständig** entwickelt:

> **https://github.com/grapefruit89/mediNix**

Dieser Ordner ist eine **eingefrorene Kopie**. Er wird nicht mehr gepflegt.

## Was hier zu tun ist

**Nichts.** Änderungen am Medienstack gehören nach mediNix.

Wenn du gerade dabei bist, hier eine Datei zu ändern: **halt an.** Die Änderung
geht in mediNix verloren, sobald Nix-Grok umgestellt wird — oder schlimmer, sie
bleibt hier liegen und niemand weiß mehr, welche der beiden Fassungen stimmt.

## Warum nicht gelöscht?

Bewusste Entscheidung des Repo-Eigentümers: nichts wird gelöscht, was noch
irgendwo referenziert sein könnte. Der Ordner bleibt vollständig liegen,
inklusive Git-Historie.

**Ehrliche Einschränkung:** Diese Markierung *verhindert* das Auseinanderdriften
nicht — sie macht es nur sichtbar. Wer hier in sechs Monaten etwas ändert, hat
trotzdem zwei Wahrheiten. Der einzige Unterschied ist, dass er es merkt.

## Warum wird noch nicht umgestellt?

Der saubere Endzustand wäre: mediNix als Flake-Input in `Nix-Grok/flake.nix`,
und `machines/q958/default.nix` importiert `inputs.mediNix.nixosModules.default`
statt des lokalen Pfads.

Das passiert **bewusst noch nicht.** Erst soll mediNix eigenständig laufen —
mit eigenem Flake, eigenem Test, auf echter Hardware verifiziert. Es jetzt
schon einzuhängen würde die Kopplung wiederherstellen, die gerade aufgelöst
werden soll.

Bildlich: Nix-Grok ist Burgfried mit Mauer und Bogenschützen. mediNix soll der
Burgfried allein sein — aber ein bewohnbarer. Erst wenn er allein steht, wird
die Mauer wieder angebaut.

## Stand von mediNix (2026-07-20)

| | |
|---|---|
| Evaluiert | ✅ `nix eval` fehlerfrei |
| Gebaut | ✅ vollständige System-Closure auf q958 |
| Gestartet | ❌ noch kein Dienst lief je |
| `flake.nix` | ✅ vorhanden (Issue #11) |

## Der Umstellungsweg, wenn es soweit ist

1. `mediNix` als Input in `Nix-Grok/flake.nix` eintragen
2. In `machines/q958/default.nix`:
   `../../modules/50-media` → `inputs.mediNix.nixosModules.default`
   (`compat-my.nix` liegt in mediNix und bleibt der Adapter `my.*` → `grapefruitMedia.*`)
3. Dry-Build auf q958
4. Erst danach entscheiden, ob dieser Ordner verschwindet

## Verweise

- Lagekarte: `STATUS.md` (hier und in mediNix)
- Regeln: `AGENTS.md` — insbesondere Regel −1: nur `main`, keine Branches
- Einbinden ins Repo: aktuell noch `machines/q958/default.nix` Zeile 40/41
