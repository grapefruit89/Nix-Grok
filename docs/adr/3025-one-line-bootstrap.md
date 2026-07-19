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

Drei Stufen, **absteigend nach Empfehlung**. Stufe 0 ist die eigentliche Antwort;
Stufe 1 ist der gewünschte Komfort; Stufe 2 ist die Kür.

---

## Stufe 0 — Ohne Skript: `nixos-anywhere` *(empfohlen)*

Es gibt bereits ein Werkzeug, das genau das tut, und zwar **von deinem Laptop aus**,
ohne dass du am Zielrechner etwas tippst:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake github:grapefruit89/Nix-Grok#q958 \
  root@192.168.2.73
```

Was dabei passiert: nixos-anywhere verbindet sich per SSH mit dem Live-System,
lädt einen Kexec-Installer nach, führt disko aus, installiert und rebootet.

**Warum das die beste Variante ist:**

| Punkt | Bedeutung |
|-------|-----------|
| **Kein Code von uns** | Kein Skript, das wir pflegen, hosten und absichern müssen |
| **Kein `curl \| bash`** | Der Flake ist per Git-Hash festgenagelt, nicht ein Text von einem Webserver |
| **Vom Laptop aus** | Tastatur, Copy-Paste, Terminal-Historie — nicht auf einer Konsole mit `de-latin1` |
| **Upstream gewartet** | nix-community, nicht wir |
| **Läuft auch remote** | Derselbe Befehl funktioniert später gegen einen Hetzner-Server |

Nach ADR-032 (*OS-native-first*) ist das Rangstufe 3 — „eigenständiges
spezialisiertes Tool". Ein selbstgeschriebenes Skript wäre Rangstufe 5.
**Die Rangfolge sagt eindeutig: Stufe 0.**

**Voraussetzung:** Auf dem Ziel läuft ein SSH-erreichbares Linux mit root-Key.
Genau das liefert unsere ISO (siehe Stufe 2) bereits ab Boot.

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
> Stufe 0. Dort ist der Flake-Hash die Vertrauensanker, nicht ein Webserver.

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

Der anstehende q958-Reinstall ist der erste echte Testfall. Reihenfolge:

1. **Heute** von Hand — `disko-q958.sh plan`, dann `install`. Der Weg muss
   einmal manuell funktionieren, bevor er automatisiert wird. Ein Skript, das
   einen ungetesteten Ablauf automatisiert, automatisiert einen Fehler.
2. **Danach** wird genau dieser verifizierte Ablauf zu `scripts/bootstrap.sh` —
   nicht vorher, und ohne Erweiterungen.
3. **Dann** Worker + ISO-Integration.

---

## Konsequenzen

**Positiv**

- Der Einzeiler existiert und ist trotzdem 40 statt 800 Zeilen
- `get.m7c5.de` ist Doku und Quelle zugleich
- Stufe 0 bleibt für alles Ernste verfügbar und braucht keine Wartung
- Der Rettungs-Stick kann installieren, ohne Netz

**Negativ / offen**

- Ein weiterer öffentlicher Endpunkt, der gewartet sein will
- `curl | bash` bleibt ein Kompromiss — bewusst eingegangen, oben begründet
- Secrets bleiben manuell, bis die TPM2-Migration steht
- Der Worker koppelt die Installation an Cloudflare-Verfügbarkeit
  (Stufe 0 und Stufe 2 sind davon unabhängig — deshalb bleiben beide bestehen)

---

## Nicht gewählte Alternativen

| Alternative | Warum nicht |
|-------------|-------------|
| **Großes Bash-Installskript nach CasaOS-Vorbild** | Verschiebt Logik aus dem Flake in unwartbares, nicht reproduzierbares Bash. Widerspricht „Declarative Core + Surgical Glue" direkt. |
| **Eigener Installer-Webservice** | Massiv mehr Angriffsfläche und Wartung für null Zusatznutzen gegenüber einem statischen Worker. |
| **Nur die ISO, kein Einzeiler** | Deckt den Fall „fremde Maschine, kein Stick zur Hand" nicht ab. |
| **`nix-shell`-Installer statt `curl`** | Setzt Nix auf dem Zielsystem voraus — hat man da schon Nix, nimmt man direkt Stufe 0. |
