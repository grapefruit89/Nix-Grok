# ---
# id: 3025
# title: "One-Line-Bootstrap — get.m7c5.de"
# status: "proposed"
# date: "2026-07-19"
# supersedes: []
# related: [3024, 5030]
# tags: ["bootstrap", "disko", "installation", "dx"]
# error_pattern: "get.m7c5.de|bootstrap|nixos-anywhere"
# ---

# ADR-3025 — One-Line-Bootstrap

## Kontext

Wunsch, wörtlich:

> „einfach wie bei casa os `curl -fsSL https://get.casaos.io | sudo bash` auf dem
> NixOS-Rechner bzw. Boot-Stick eingeben und dann nachher mein fertiges Media-Repo
> fix und fertig dort haben — `curl -fsSL https://get.m7c5.de | sudo bash`"

Das Ziel ist richtig. Der Weg dorthin ist auf NixOS aber ein **anderer** als bei
CasaOS — und zwar ein deutlich besserer. Das ist der Kern dieses ADR.

---

## Warum CasaOS ein Skript braucht und wir nicht

CasaOS läuft auf Debian/Ubuntu. Dort gibt es **keine Beschreibung des Zielzustands**.
Das Installationsskript ist deshalb ein Programm, das den Zustand Schritt für
Schritt *herstellt*: Repos eintragen, Docker installieren, Dienste anlegen,
Konfigurationen schreiben, Units starten. Rund 800 Zeilen Bash, in denen jeder
Schritt schiefgehen kann und jeder zweite Schritt nicht wiederholbar ist.

Bei uns **existiert die Beschreibung des Zielzustands bereits** — sie heißt
`flake.nix#q958`. Der komplette Media-Stack, alle Dienste, Ingress, Härtung,
Provisionierung stehen darin. Es gibt nichts „herzustellen". Es gibt nur:

1. Platte partitionieren  → `disko`
2. Zustand anwenden       → `nixos-install --flake …`

Zwei Befehle. Der Rest ist Nix.

> **Konsequenz für das Design:** Unser Bootstrap-Skript darf **nicht** die Logik
> enthalten. Es ist reine *Surgical Glue* im Sinne der Repo-Philosophie: es
> orchestriert zwei Aufrufe und tut sonst nichts. Jede Zeile Logik, die ins
> Skript wandert, ist eine Zeile, die nicht mehr deklarativ und nicht mehr
> reproduzierbar ist.
>
> Ein 800-Zeilen-Bash-Installer wäre auf NixOS ein Rückschritt, kein Fortschritt.

---

## Entscheidung

Vier Stufen. **Welche gilt, hängt davon ab, wie du an die Maschine kommst** —
nicht davon, welche technisch eleganter ist. Das ist der Punkt, den ein früherer
Entwurf dieses ADR falsch hatte (siehe „Verworfene Rangfolge" am Ende).

| Situation | Stufe |
|-----------|-------|
| Ich sitze davor / Stick steckt drin | **0 — SSH in die Live-ISO** |
| Ich will gar nichts tippen, Stick steckt drin | **2 — ISO-Menü** |
| Fremde Kiste, kein Stick zur Hand | **1 — Einzeiler** |
| Kein physischer Zugang (Hoster) | **3 — nixos-anywhere** |

---

## Stufe 0 — SSH in die laufende Live-ISO *(der Normalfall)*

Wenn die Installer-ISO gebootet ist, ist SSH **bereits offen und der Key liegt
drin** (so ist `iso.nix` gebaut). Damit ist nichts weiter nötig:

```bash
ssh nixos@192.168.2.73          # oder root@ — beide Keys sind hinterlegt

sudo /etc/nixos/scripts/disko-q958.sh plan      # Trockenlauf, schreibt nichts
sudo /etc/nixos/scripts/disko-q958.sh install   # ZERSTOEREND
sudo nixos-install --flake /etc/nixos#q958 --impure --no-root-passwd
```

**Das ist die ganze Installation.** Kein zusätzliches Werkzeug, kein Skript, kein
Webserver, keine zweite Nix-Umgebung. Du tippst auf deiner eigenen Tastatur, weil
du per SSH von deinem Arbeitsrechner draufgehst — das Tastaturlayout auf der
Konsole ist damit egal.

> **Warum das die Standardantwort ist:** Sobald die ISO läuft, ist der schwierige
> Teil bereits erledigt. Alles, was danach kommt, sind zwei Befehle. Jede weitere
> Werkzeugschicht löst ein Problem, das an dieser Stelle nicht mehr existiert.

**Voraussetzung:** Stick gebootet, Netzwerk per DHCP, IP bekannt (Router-Oberfläche,
oder nach Stufe 2 direkt auf dem Bildschirm).

---

## Stufe 3 — `nixos-anywhere` *(nur ohne physischen Zugang)*

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake github:grapefruit89/Nix-Grok#q958 \
  root@<ip>
```

nixos-anywhere verbindet sich mit einem **beliebigen laufenden Linux**, lädt einen
Kexec-Installer nach, führt disko aus, installiert und rebootet.

**Wofür es gedacht ist:** Ein Server bei einem Hoster, in den du keinen USB-Stick
stecken kannst. Rescue-Debian rein, ein Befehl, NixOS raus. Dafür ist es
hervorragend.

**Warum es hier meistens *nicht* passt** — zwei Voraussetzungen, die in unserem
Setup unangenehm sind:

1. **Nix auf der steuernden Maschine.** Der Arbeitsrechner läuft Windows und hat
   kein Nix. Es gibt eine WSL-NixOS-Instanz (Nix 2.34.7, Flakes aktiv,
   2026-07-19 geprüft) — damit ginge es, aber über eine zusätzliche Schicht.
2. **Es löst ein Problem, das wir nicht haben.** nixos-anywhere stellt genau den
   Zustand her, in dem die gebootete Live-ISO ohnehin schon ist: SSH-erreichbares
   Linux mit Nix. Es davorzusetzen heißt, den Umweg zu gehen, um am
   Ausgangspunkt anzukommen.

> **Merksatz:** nixos-anywhere ersetzt den USB-Stick. Wenn der Stick schon steckt,
> ersetzt es nichts.

**Wann es hier trotzdem relevant wird:** sobald ein zweiter Rechner oder ein
gemieteter Server dazukommt. Dann ist q958 selbst die steuernde Maschine — mit
Nix an Bord und ohne WSL-Umweg.

---

## Stufe 1 — Der gewünschte Einzeiler

Trotzdem sinnvoll, denn Stufe 0 verlangt einen zweiten Rechner mit Nix. Wenn du
schon vor der Kiste sitzt, willst du tippen können:

```bash
curl -fsSL https://get.m7c5.de | sudo bash
```

### Das Skript — vollständig, und genau so kurz soll es bleiben

```bash
#!/usr/bin/env bash
# https://get.m7c5.de  —  q958 Bootstrap
# Quelle: github.com/grapefruit89/Nix-Grok  → scripts/bootstrap.sh
set -euo pipefail

FLAKE="${FLAKE:-github:grapefruit89/Nix-Grok}"
HOST="${HOST:-q958}"

# ── 1. Sanity ──────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "Als root ausfuehren."; exit 1; }
command -v nix >/dev/null || { echo "Kein nix — NixOS-ISO booten."; exit 1; }

# ── 2. Zielplatte: NIE raten ───────────────────────────────────────────────
# Der einzige zerstoerende Schritt. Deshalb der einzige, der nachfragt.
if [[ -z "${DISK:-}" ]]; then
  echo "Verfuegbare Platten:"; lsblk -dno NAME,SIZE,MODEL | sed 's/^/  \/dev\//'
  read -rp "Zielplatte (wird VOLLSTAENDIG geloescht): " DISK
fi
[[ -b "$DISK" ]] || { echo "$DISK ist kein Blockgeraet."; exit 1; }

echo
echo "  Flake : $FLAKE#$HOST"
echo "  Platte: $DISK  ($(lsblk -dno SIZE "$DISK"))"
echo
read -rp "ALLE DATEN AUF $DISK WERDEN GELOESCHT. Tippe 'ja': " ok
[[ "$ok" == "ja" ]] || { echo "Abgebrochen."; exit 1; }

# ── 3. Partitionieren — Logik liegt im Flake, nicht hier ───────────────────
nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- \
  --mode destroy,format,mount \
  --flake "$FLAKE#$HOST" \
  --arg device "\"$DISK\""

# ── 4. Installieren ────────────────────────────────────────────────────────
nixos-install --flake "$FLAKE#$HOST" --no-root-passwd --no-channel-copy

echo
echo "Fertig. 'reboot', danach:  ssh jarvis@$HOST.local"
echo "NICHT VERGESSEN: profile.local.nix + /var/lib/secrets einspielen."
```

**Rund 40 Zeilen, davon die Hälfte Sicherheitsabfragen.** Das ist die
Obergrenze — wächst es darüber hinaus, gehört die neue Logik in den Flake.

### Hosting: Cloudflare Worker

Die Domain liegt bereits bei Cloudflare, ein Worker kostet nichts und braucht
keinen Server. Der Charme: **derselbe URL liefert je nach Aufrufer etwas anderes.**

```js
// Worker an get.m7c5.de gebunden
const RAW = "https://raw.githubusercontent.com/grapefruit89/Nix-Grok/main/scripts/bootstrap.sh";

export default {
  async fetch(req) {
    const ua = req.headers.get("user-agent") || "";
    const script = await (await fetch(RAW, { cf: { cacheTtl: 300 } })).text();

    // Browser → lesbare Seite MIT dem Skript im Klartext.
    // Wer den Einzeiler kopiert, soll vorher sehen koennen, was er ausfuehrt.
    if (/Mozilla|Chrome|Safari|Firefox/i.test(ua)) {
      return new Response(page(script), {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }
    // curl / wget → nacktes Skript
    return new Response(script, {
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },
};
```

Damit ist `https://get.m7c5.de` **gleichzeitig** die Doku-Seite und die
Skript-Quelle — und niemand muss ein Skript ausführen, das er nicht lesen kann.

### Zu `curl | bash` — die ehrliche Einordnung

Es ist zu Recht verpönt: du führst als root aus, was ein Server dir in dem
Moment schickt, ungeprüft und ohne Versionierung.

Was das Risiko hier **klein** hält:

- HTTPS-only, HSTS, Cloudflare vor GitHub — kein MITM-Fenster
- Die einzige interessante Zielmaschine ist eine, die du **ohnehin gerade
  plattmachst** — es gibt nichts zu stehlen
- Der Worker liefert genau die Datei aus dem öffentlichen Repo. Manipulation
  wäre im Git-Verlauf sichtbar
- Im Browser steht dieselbe Datei lesbar auf der Seite

Was es **nicht** wegdiskutiert: Wer GitHub-Zugriff oder den Cloudflare-Account
übernimmt, führt root-Code auf deiner Kiste aus. Deshalb:

> **Regel:** Der Einzeiler ist für die eigene Kiste im eigenen LAN. Für alles
> andere — fremde Hardware, Server beim Hoster, Maschinen mit Daten — gilt
> Stufe 0 bzw. 3. Dort ist der Flake-Hash der Vertrauensanker, nicht ein Webserver.

Wer es strenger will, kann jederzeit:

```bash
curl -fsSL https://get.m7c5.de -o b.sh && less b.sh && sudo bash b.sh
```

Das ist derselbe Komfort minus zwei Sekunden — und beseitigt den Einwand
vollständig.

---

## Stufe 2 — In die ISO backen

Die Krönung: gar nichts tippen. Die eigene Installer-ISO (`iso.nix` liegt
bereits unter `Downloads\nixos-installer-iso\`) bekommt das Skript mitgeliefert
und zeigt es beim Login an.

```nix
# Ergaenzung zu iso.nix
environment.systemPackages = [
  (pkgs.writeShellScriptBin "install-q958"
    (builtins.readFile ./scripts/bootstrap.sh))
];

# Beim Konsolen-Login sichtbar
programs.bash.loginShellInit = ''
  cat <<'EOF'
  ┌──────────────────────────────────────────────┐
  │  q958 Installer                              │
  │                                              │
  │    install-q958      ← installiert alles     │
  │                                              │
  │  IP: $(ip -4 -br addr show scope global)     │
  │  SSH ist an, Key ist hinterlegt.             │
  └──────────────────────────────────────────────┘
  EOF
'';
```

Damit ist der Stick der **Rettungs- und Installations-Stick in einem** — genau
das erklärte Ziel („dieser Stick wird dann fortan mein 0815 Rettungs-Stick").
Ohne Netzwerk, ohne `curl`, ohne Tastaturlayout-Gefummel.

---

## Die Lücke, die kein Einzeiler schließt

**Secrets.** `profile.local.nix` ist gitignored, `/var/lib/secrets` liegt nicht
im Repo. Das ist beabsichtigt und darf sich nicht ändern.

Ein öffentliches Bootstrap-Skript kann daran **prinzipiell** nicht herankommen.
Nach dem Durchlauf steht also ein vollständiges System — aber ohne Zugangsdaten.

Drei Wege, in dieser Reihenfolge:

1. **Manuell** (heute): Skript endet mit dem Hinweis, du kopierst per `scp`.
   Ehrlich, aber du musst dran denken.
2. **`--secrets`-Flag**: optionaler Parameter mit einem Pfad (USB-Stick,
   `scp`-Ziel). Das Skript spielt ein, wenn angegeben.
3. **Zielbild:** Secrets liegen mit `systemd-creds` TPM2-versiegelt **auf der
   Maschine**. Dann übersteht sie eine Neuinstallation nicht — aber es gibt einen
   *einen* definierten Wiederherstellungspunkt statt dreizehn loser Dateien.
   Das ist ohnehin die Richtung aus `ROADMAP-creds-migration.md`.

> Solange Weg 3 nicht steht, endet **jeder** Bootstrap mit der Zeile
> „NICHT VERGESSEN: profile.local.nix + /var/lib/secrets einspielen." Das
> Skript darf nicht so tun, als sei es fertig, wenn es das nicht ist.

---

## Was das für heute bedeutet

Der anstehende q958-Reinstall ist der erste echte Testfall — und er läuft
**Stufe 0**, weil die Live-ISO bereits gebootet und `192.168.2.73:22`
erreichbar ist.

1. **Heute** von Hand über SSH — `disko-q958.sh plan`, dann `install`,
   dann `nixos-install`. Der Weg muss einmal manuell funktionieren, bevor er
   automatisiert wird. Ein Skript, das einen ungetesteten Ablauf automatisiert,
   automatisiert einen Fehler.
2. **Danach** wird genau dieser verifizierte Ablauf zu `scripts/bootstrap.sh` —
   nicht vorher, und ohne Erweiterungen.
3. **Dann** Worker + ISO-Integration (Stufe 1 und 2).
4. **Stufe 3** wird erst interessant, wenn eine Maschine ohne physischen Zugang
   dazukommt. Dann ist q958 selbst der Steuerrechner.

---

## Konsequenzen

**Positiv**

- Der Normalfall braucht **gar kein neues Werkzeug** — zwei Befehle über SSH
- Der Einzeiler existiert trotzdem, und ist 40 statt 800 Zeilen
- `get.m7c5.de` ist Doku und Quelle zugleich
- Der Rettungs-Stick kann installieren, ohne Netz
- Stufe 3 bleibt dokumentiert für den Fall, dass sie gebraucht wird

**Negativ / offen**

- Vier Stufen sind erklärungsbedürftig — deshalb die Tabelle ganz oben
- Ein weiterer öffentlicher Endpunkt, der gewartet sein will
- `curl | bash` bleibt ein Kompromiss — bewusst eingegangen, oben begründet
- Secrets bleiben manuell, bis die TPM2-Migration steht
- Der Worker koppelt Stufe 1 an Cloudflare-Verfügbarkeit
  (Stufen 0, 2 und 3 sind davon unabhängig — deshalb bleiben sie bestehen)

---

## Verworfene Rangfolge *(Korrektur am eigenen Entwurf, 2026-07-19)*

Die erste Fassung dieses ADR führte `nixos-anywhere` als „Stufe 0, objektiv beste
Variante" und begründete das mit ADR-032 (*OS-native-first*): fertiges Tool =
Rang 3, eigenes Skript = Rang 5, also gewinnt das Tool.

**Das war ein Fehlschluss.** Die Rangfolge in ADR-032 entscheidet, *womit* man
ein Problem löst — nicht, *ob* man es hat. Sie setzt voraus, dass es das Problem
überhaupt gibt.

Zwei ungeprüfte Annahmen steckten darin:

1. **„vom Laptop aus"** — der Arbeitsrechner ist Windows und hat kein Nix.
   nixos-anywhere braucht Nix auf der steuernden Seite. (Eine WSL-NixOS-Instanz
   existiert, Nix 2.34.7 — aber das ist eine Zusatzschicht, kein Vorteil.)
2. **Das Problem existierte nicht.** nixos-anywhere stellt ein SSH-erreichbares
   Linux mit Nix auf dem Ziel her. Die gebootete Live-ISO *ist* das bereits.

Aufgefallen ist es durch die Rückfrage: *„wie komme ich dann mit dem NixOS auf
die Maschine?"* — eine Frage, die die Empfehlung sofort als unvollständig
entlarvt hat.

> **Generalisierte Regel:** Eine Werkzeugempfehlung ist erst vollständig, wenn
> die **Voraussetzungen des Werkzeugs gegen die tatsächliche Umgebung geprüft**
> sind. „Rang 3 schlägt Rang 5" gilt nur bei gleichem Problem. Ein Werkzeug, das
> den Ist-Zustand herstellt, ist kein Fortschritt.
>
> Ausformuliert in `docs/SUNDAY-LEARNINGS.md`, Eintrag C4.

---

## Nicht gewählte Alternativen

| Alternative | Warum nicht |
|-------------|-------------|
| **Großes Bash-Installskript nach CasaOS-Vorbild** | Verschiebt Logik aus dem Flake in unwartbares, nicht reproduzierbares Bash. Widerspricht „Declarative Core + Surgical Glue" direkt. |
| **Eigener Installer-Webservice** | Massiv mehr Angriffsfläche und Wartung für null Zusatznutzen gegenüber einem statischen Worker. |
| **Nur die ISO, kein Einzeiler** | Deckt den Fall „fremde Maschine, kein Stick zur Hand" nicht ab. |
| **`nix-shell`-Installer statt `curl`** | Setzt Nix auf dem Zielsystem voraus — hat man da schon Nix, ist man bereits in Stufe 0. |
| **nixos-anywhere als Standardweg** | Siehe „Verworfene Rangfolge". Ersetzt den USB-Stick; wenn der steckt, ersetzt es nichts. |
