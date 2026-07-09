# Secrets Rotator — Design Spec

**Datum:** 2026-07-09
**Status:** Approved

---

## Problem

`profile.local.nix` manuell per SSH editieren ist fehleranfällig, setzt Terminal-Zugang
voraus und macht Secret-Rotation unbequem. Ziel: alle Secrets bequem über den Browser
setzen — einmalig oder zur Rotation — ohne dass Secrets jemals den Server verlassen.

---

## Scope

**Phase 1 (dieses Dokument):** Secrets-Rotation-Tool — alle `profile.local.nix`-Felder
setzbar, Einbahnstraße, kein Lesen/Anzeigen bestehender Werte.

**Phase 2 (später, Stufe 9+):** TPM-sealed systemd-creds Rotation. Separates Dokument.

---

## Architektur

```
Browser (LAN-only)
  │  POST /api/secret  (Key → Backend, nie zurück)
  ▼
FastAPI Backend  (Python, systemd-service, port 8765, nur LAN-IP)
  ├── 1. Echten API-Call machen (wo möglich)
  ├── 2. profile.local.nix atomar schreiben
  ├── 3. systemd-creds schreiben
  └── 4. Rebuild-Debounce-Timer starten/resetten (3 min)

Response: { ok: true } oder { ok: false, error: "..." }

profile.local.nix  ← Persistenz, überlebt Rebuilds
systemd-creds      ← sofort wirksam
nixos-rebuild      ← nach 3 min Inaktivität, liest profile.local.nix
```

**Einbahnstraße:** Das Backend gibt niemals Secret-Werte zurück. Kein GET auf Secrets.
Kein localStorage im Frontend. Nach Toast ist das Input-Feld leer.

---

## NixOS-Modul

```
my.services.secrets-rotator
  enable   = true ab Rollout-Stufe 1
  port     = 8765
  bindAddr = p.network.lan.ip  (nur LAN, nie 0.0.0.0)
```

Kein Caddy-Reverse-Proxy. Direktzugriff über `http://192.168.2.73:8765`,
Firewall erlaubt Port 8765 nur aus LAN-CIDRs.

---

## Frontend

**Eine einzige HTML-Datei**, ausgeliefert vom FastAPI-Backend. Kein npm, kein Build-Step,
kein Framework. Vanilla JS.

### Layout pro Zeile

| Spalte 1 | Spalte 2 | Spalte 3 |
|---|---|---|
| Name + Beschreibung + Link zur API-Key-Seite | Input-Feld | "Abschicken"-Button |

**Regex-Verhalten:**
- Regex läuft live clientseitig beim Tippen
- Feld färbt sich: grün (Muster passt) / neutral (kein Match)
- Button ist **immer klickbar**, unabhängig vom Regex-Status
- Regex-Match → Button wird **automatisch gedrückt** (auto-submit)
- Button ist **jederzeit manuell klickbar**, auch ohne Regex-Match
- Veraltetes Regex-Pattern: UI bleibt funktionsfähig, Backend entscheidet

**Warum kein Disable:** Wenn sich ein Key-Format ändert, bricht ein deaktivierter Button
den Workflow ohne sichtbaren Grund. Das Backend validiert ohnehin via echtem API-Call.

### Gruppenstruktur

```
── Domain ──────────────────────────────────────
  base-Domain         [input]  [Abschicken]
  nixSubdomain        [toggle] [Abschicken]

── Cloudflare ──────────────────────────────────
  API Token           [input]  [Abschicken]

── Restic (Koofr S3) ───────────────────────────
  Repository-URL      [input]  [Abschicken]
  AWS Access Key ID   [input]  [Abschicken]
  AWS Secret Key      [input]  [Abschicken]

── VPN ─────────────────────────────────────────
  PrivadoVPN WG Key   [input]  [Abschicken]

── Usenet ──────────────────────────────────────
  Host                [input]  [Abschicken]
  Username            [input]  [Abschicken]
  Passwort            [input]  [Abschicken]

── Media-Indexer ───────────────────────────────
  TreasureMaps Key    [input]  [Abschicken]
```

**Status-Indikator je Feld:** ⬜ nicht gesetzt / ✅ gesetzt — nur ob ein cred-File
existiert, niemals der Wert selbst.

### Toast-Notifications

- ✅ grün: "Cloudflare Token gespeichert — Rebuild in 2:47"
- ❌ rot: "Cloudflare Token ungültig — Zone nicht gefunden"
- 🔄 neutral: "Rebuild läuft..."

### Rebuild-Countdown

Leiste unten: "Rebuild in **2:47** — [Jetzt] [Abbrechen]"
Timer startet beim ersten Save, resettet bei jedem weiteren. Läuft im Backend.

---

## Backend API

```
POST /api/secret/{field}    body: { value: "..." }
  → validiert (API-Call wo möglich)
  → schreibt profile.local.nix (atomar: tmp → rename)
  → schreibt systemd-creds
  → response: { ok: bool, error?: str, rebuildIn: int }

GET  /api/status
  → { fields: { cloudflare_token: "set"|"unset", ... } }
  → niemals Werte, nur Existenz

POST /api/rebuild/now       → sofort rebuild
POST /api/rebuild/cancel    → Timer stoppen
GET  /api/rebuild/status    → { secondsRemaining: int }
```

---

## Validation pro Feld

| Feld | Regex (visuell) | Backend-Validation |
|---|---|---|
| CF API Token | `^[a-zA-Z0-9_-]{32,}$` | GET /zones (erwartet 200) |
| Domain base | `^[a-z0-9.-]+\.[a-z]{2,}$` | keiner (Format reicht) |
| WireGuard Key | `^[A-Za-z0-9+/]{43}=$` | keiner (Base64, 44 Zeichen) |
| Restic Repo | `^s3:` | keiner (Format reicht) |
| Restic AWS Key | `^[A-Z0-9]{16,}$` | keiner |
| Usenet Host | `^[a-z0-9.-]+$` | TCP-Connect Port 563 |
| TreasureMaps Key | `^[a-zA-Z0-9]{16,}$` | GET /api/v1/indexer (200?) |

---

## Atomares Schreiben in profile.local.nix

Parser: minimaler String-Replacer — kein vollständiger Nix-Parser. Jedes Feld hat
ein eindeutiges Muster (`fieldName = "...";`) das sicher ersetzt werden kann.
tmp-Datei + `os.rename()` — atomar, keine halben Schreibvorgänge.

---

## Sicherheit

- **LAN-only:** bindAddr = LAN-IP, kein Caddy-Proxy, Firewall LAN-CIDRs only
- **Kein Auslesen:** GET /api/status gibt nur "set"/"unset", niemals Werte
- **Kein Frontend-State:** Input-Felder nach Toast geleert, kein localStorage
- **Atomares Schreiben:** tmp + rename verhindert korrupte profile.local.nix
- **Kein WAN:** Keine Caddy-Route für diesen Service

---

## Nicht in Scope

- Secret-Anzeige / Export
- OIDC / oauth2-proxy Credentials (werden im Browser direkt gesetzt)
- Media API Keys (*arr, Jellyfin) — einmalig, per SSH beim Setup OK
- TPM-sealed Rotation (Phase 2, Stufe 9+)
