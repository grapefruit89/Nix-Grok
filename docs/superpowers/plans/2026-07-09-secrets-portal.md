# Secrets Portal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Das bestehende `secrets-portal` Go-Paket um profile.local.nix-Persistenz, Provision-Restart und Rebuild-Debounce-Timer erweitern — sowie für q958 aktivieren und konfigurieren.

**Architecture:** Go-Binary lauscht auf Unix-Socket `/run/secrets-portal/secrets-portal.sock`. Caddy (internal zone = LAN-only) proxied darauf. Bei erfolgreichem Seal: (1) systemd-creds schreiben, (2) profile.local.nix atomar aktualisieren, (3) q958-secrets-provision neu starten, (4) Rebuild-Debounce-Timer zurücksetzen. Nach 3 min Inaktivität: `nixos-rebuild switch`.

**Tech Stack:** Go (stdlib only), Vanilla JS/HTML, NixOS-Modul, Caddy internal zone

## Global Constraints

- Go: stdlib only, kein vendor directory — `vendorHash = null` bleibt
- Kein Caddy-direktzugriff von WAN: zone = "internal" erzwingt LAN-Beschränkung
- Atomares Schreiben in profile.local.nix: tmp + os.Rename, niemals direktes Überschreiben
- Kein Key darf ohne erfolgreiche Validation (API-Call oder Format-Check) geschrieben werden
- Button ist immer klickbar — `disabled` darf nur während eines laufenden Requests gesetzt sein
- Regex: nur Feldeinfärbung + auto-submit Trigger; kein Gate

---

## File Map

| Datei | Änderung |
|---|---|
| `packages/secrets-portal/main.go` | ProfilePattern/ProfileType in SecretDef, writeProfile(), rebuildTimer, /api/rebuild/* Endpoints, PROVISION_SERVICE + REBUILD_FLAKE Env |
| `packages/secrets-portal/static/index.html` | Button nie initial disabled, auto-submit bei Regex-Match (500ms debounce), Rebuild-Countdown UI |
| `modules/20-security/2029-secrets-portal.nix` | profilePattern/profileType Optionen in secretDefType, PROFILE_LOCAL_PATH + PROVISION_SERVICE + REBUILD_FLAKE in Environment, ReadWritePaths erweitern |
| `lib/services-spec.nix` | secrets-portal Eintrag (socket + internal zone) |
| `machines/q958/default.nix` | secrets-portal.enable + vollständige secrets-Liste |
| `machines/q958/rollout.nix` | my.services.secrets-portal.enable = erstAb 1 |

---

## Task 1: Button-Verhalten und Auto-Submit in index.html

**Files:**
- Modify: `packages/secrets-portal/static/index.html`

**Interfaces:**
- Consumes: /api/validate, /api/seal (unverändert)
- Produces: Button immer klickbar; Regex-Match → 500ms delay → seal() aufrufen

- [ ] **Schritt 1: Button initial nicht disabled setzen**

In `renderSecrets()`, Zeile mit `disabled` im button-Tag:
```html
<!-- VORHER: -->
<button class="btn-seal" id="btn-${s.name}" disabled
  onclick="seal('${s.name}')">Versiegeln</button>

<!-- NACHHER: -->
<button class="btn-seal" id="btn-${s.name}"
  onclick="seal('${s.name}')">Setzen</button>
```

- [ ] **Schritt 2: onInput — kein btn.disabled, stattdessen auto-submit bei Match**

Die gesamte `onInput`-Funktion ersetzen:
```javascript
const debounceTimers = {};

function onInput(name) {
  const s = secretsMap[name];
  const inp = document.getElementById('val-' + name);
  const err = document.getElementById('err-' + name);
  const val = inp.value.trim();

  clearTimeout(debounceTimers[name]);

  if (s.regex) {
    try {
      const ok = new RegExp(s.regex).test(val);
      inp.className = ok ? 'state-valid' : (val.length > 0 ? 'state-invalid' : '');
      err.textContent = (ok || val.length === 0) ? '' : 'Format nicht erkannt — manuell prüfen';
      if (ok && val.length > 0) {
        debounceTimers[name] = setTimeout(() => seal(name), 500);
      }
    } catch {
      inp.className = 'state-valid';
    }
  } else {
    inp.className = val.length >= 8 ? 'state-valid' : (val.length > 0 ? 'state-invalid' : '');
    err.textContent = (val.length > 0 && val.length < 8) ? 'Zu kurz (min. 8 Zeichen)' : '';
  }
}
```

- [ ] **Schritt 3: seal() — kein permanentes disable, nur während Request**

In `seal()` die erste Zeile ändern:
```javascript
async function seal(name) {
  const inp = document.getElementById('val-' + name);
  const btn = document.getElementById('btn-' + name);
  const err = document.getElementById('err-' + name);
  const val = inp.value.trim();
  if (!val) return;
  if (btn.dataset.inflight) return;  // Verhindert Doppel-Submit

  btn.dataset.inflight = '1';
  btn.className = 'btn-seal state-checking';
  btn.textContent = 'Prüfe…';
  err.textContent = '';
  // ... Rest unverändert
```

Am Ende von seal(), nach `setBtn()` und `setTimeout`:
```javascript
  } finally {
    delete btn.dataset.inflight;
  }
```

- [ ] **Schritt 4: secretsMap für onInput bereitstellen**

In `renderSecrets()` nach `const secrets = await fetch(...)`:
```javascript
const secretsMap = {};
for (const s of data) secretsMap[s.name] = s;
window.secretsMap = secretsMap;
```

- [ ] **Schritt 5: Verifikation — manuell**

```bash
cd /etc/nixos && sudo nix build .#secrets-portal 2>&1 | tail -5
```
Erwartung: Build erfolgreich, kein Fehler.

- [ ] **Schritt 6: Commit**

```bash
cd /etc/nixos
sudo git add packages/secrets-portal/static/index.html
sudo git commit -m "feat(secrets-portal): button immer klickbar, auto-submit bei Regex-Match"
```

---

## Task 2: Profile-Write und Provision-Restart in main.go

**Files:**
- Modify: `packages/secrets-portal/main.go`

**Interfaces:**
- Consumes: PROFILE_LOCAL_PATH env var (Pfad zu profile.local.nix), PROVISION_SERVICE env var
- Produces: writeProfile(path, pattern, value, ptype) schreibt Feld atomar; handleSeal ruft writeProfile + systemctl restart auf

- [ ] **Schritt 1: SecretDef um ProfilePattern und ProfileType erweitern**

In `main.go`, `SecretDef` struct erweitern:
```go
type SecretDef struct {
    Name           string     `json:"name"`
    Label          string     `json:"label"`
    Description    string     `json:"description"`
    Link           string     `json:"link,omitempty"`
    Regex          string     `json:"regex,omitempty"`
    Validator      *Validator `json:"validator,omitempty"`
    ProfilePattern string     `json:"profile_pattern,omitempty"` // Go-Regex, group 1 = Prefix vor dem Wert
    ProfileType    string     `json:"profile_type,omitempty"`    // "string" (default) | "bool"
}
```

- [ ] **Schritt 2: Neue globale Variablen für Pfad und Service**

Nach der `var`-Deklaration von `credStore`:
```go
var (
    credStore        string
    systemdCredsBin  string
    profileLocalPath string
    provisionService string
    secrets          []SecretDef
    httpClient       = &http.Client{Timeout: 8 * time.Second}
)
```

In `main()` nach den bestehenden env()-Calls:
```go
profileLocalPath = env("PROFILE_LOCAL_PATH", "")
provisionService = env("PROVISION_SERVICE", "")
```

- [ ] **Schritt 3: writeProfile Funktion**

```go
func writeProfile(pattern, value, ptype string) error {
    if profileLocalPath == "" || pattern == "" {
        return nil
    }
    data, err := os.ReadFile(profileLocalPath)
    if err != nil {
        return fmt.Errorf("writeProfile read: %w", err)
    }

    re, err := regexp.Compile(pattern)
    if err != nil {
        return fmt.Errorf("writeProfile pattern: %w", err)
    }

    var updated string
    if ptype == "bool" {
        // Pattern: `(key\s*=\s*)(true|false)` → ersetzt zweite Gruppe
        updated = re.ReplaceAllString(string(data), "${1}"+value)
    } else {
        // Pattern: `(key\s*=\s*")[^"]*"` → fügt Wert zwischen Anführungszeichen ein
        updated = re.ReplaceAllString(string(data), "${1}"+regexp.QuoteMeta(value)+`"`)
    }

    if updated == string(data) {
        log.Printf("writeProfile: pattern %q matched nothing in %s", pattern, profileLocalPath)
        return nil // kein Fehler — Feld existiert evtl. nicht in dieser Installation
    }

    tmp := profileLocalPath + ".tmp"
    if err := os.WriteFile(tmp, []byte(updated), 0600); err != nil {
        return fmt.Errorf("writeProfile write tmp: %w", err)
    }
    if err := os.Rename(tmp, profileLocalPath); err != nil {
        os.Remove(tmp)
        return fmt.Errorf("writeProfile rename: %w", err)
    }
    log.Printf("writeProfile: updated %s via pattern %q", profileLocalPath, pattern)
    return nil
}
```

- [ ] **Schritt 4: handleSeal um writeProfile + provisionRestart erweitern**

Am Ende von `handleSeal`, nach dem `log.Printf("sealed: ...")`:
```go
    // Profile.local.nix persistieren
    if err := writeProfile(def.ProfilePattern, req.Value, def.ProfileType); err != nil {
        log.Printf("writeProfile warning for %s: %v", def.Name, err)
        // kein http.Error — cred ist bereits gesiegelt, Fehler nur loggen
    }

    // Provision-Service neu starten damit Änderungen sofort wirken
    if provisionService != "" {
        go func() {
            out, err := exec.Command("systemctl", "restart", provisionService).CombinedOutput()
            if err != nil {
                log.Printf("provision restart failed: %v — %s", err, out)
            } else {
                log.Printf("provision restarted: %s", provisionService)
            }
        }()
    }
```

- [ ] **Schritt 5: Build-Verifikation**

```bash
cd /etc/nixos && sudo nix build .#secrets-portal 2>&1 | tail -5
```
Erwartung: Kein Compile-Fehler.

- [ ] **Schritt 6: Commit**

```bash
cd /etc/nixos
sudo git add packages/secrets-portal/main.go
sudo git commit -m "feat(secrets-portal): profile.local.nix write + provision restart nach seal"
```

---

## Task 3: Rebuild-Debounce-Timer in main.go + index.html

**Files:**
- Modify: `packages/secrets-portal/main.go`
- Modify: `packages/secrets-portal/static/index.html`

**Interfaces:**
- Consumes: REBUILD_FLAKE env var (z.B. "/etc/nixos#q958")
- Produces: GET /api/rebuild/status → `{"secondsRemaining":int,"active":bool}`, POST /api/rebuild/now, POST /api/rebuild/cancel

- [ ] **Schritt 1: Timer-State und globale Variablen**

Import `"sync"` und `"time"` sind schon vorhanden. Globale Variablen ergänzen:
```go
var (
    // ... bestehende vars ...
    rebuildFlake   string
    rebuildMu      sync.Mutex
    rebuildTimer   *time.Timer
    rebuildDeadline time.Time
)
```

In `main()`:
```go
rebuildFlake = env("REBUILD_FLAKE", "")
```

- [ ] **Schritt 2: resetRebuildTimer Funktion**

```go
const rebuildDelay = 3 * time.Minute

func resetRebuildTimer() {
    if rebuildFlake == "" {
        return
    }
    rebuildMu.Lock()
    defer rebuildMu.Unlock()
    if rebuildTimer != nil {
        rebuildTimer.Stop()
    }
    rebuildDeadline = time.Now().Add(rebuildDelay)
    rebuildTimer = time.AfterFunc(rebuildDelay, runRebuild)
    log.Printf("rebuild timer reset — fires at %s", rebuildDeadline.Format("15:04:05"))
}

func runRebuild() {
    rebuildMu.Lock()
    rebuildTimer = nil
    rebuildDeadline = time.Time{}
    rebuildMu.Unlock()

    log.Printf("starting nixos-rebuild switch --flake %s", rebuildFlake)
    cmd := exec.Command("nixos-rebuild", "switch", "--flake", rebuildFlake, "--impure")
    out, err := cmd.CombinedOutput()
    if err != nil {
        log.Printf("rebuild failed: %v\n%s", err, out)
    } else {
        log.Printf("rebuild switch completed")
    }
}
```

- [ ] **Schritt 3: resetRebuildTimer in handleSeal aufrufen**

Direkt nach dem `go func() { ... provisionRestart }()` Block:
```go
    resetRebuildTimer()

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]bool{"success": true})
```

- [ ] **Schritt 4: /api/rebuild/* Endpoints registrieren**

In `main()`, nach den bestehenden `mux.HandleFunc` Zeilen:
```go
mux.HandleFunc("GET /api/rebuild/status", handleRebuildStatus)
mux.HandleFunc("POST /api/rebuild/now", handleRebuildNow)
mux.HandleFunc("POST /api/rebuild/cancel", handleRebuildCancel)
```

- [ ] **Schritt 5: Handler implementieren**

```go
func handleRebuildStatus(w http.ResponseWriter, r *http.Request) {
    rebuildMu.Lock()
    deadline := rebuildDeadline
    active := rebuildTimer != nil
    rebuildMu.Unlock()

    var remaining int
    if active {
        remaining = max(0, int(time.Until(deadline).Seconds()))
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]any{
        "active":           active,
        "secondsRemaining": remaining,
    })
}

func handleRebuildNow(w http.ResponseWriter, r *http.Request) {
    rebuildMu.Lock()
    if rebuildTimer != nil {
        rebuildTimer.Stop()
        rebuildTimer = nil
        rebuildDeadline = time.Time{}
    }
    rebuildMu.Unlock()
    go runRebuild()
    w.WriteHeader(http.StatusAccepted)
}

func handleRebuildCancel(w http.ResponseWriter, r *http.Request) {
    rebuildMu.Lock()
    if rebuildTimer != nil {
        rebuildTimer.Stop()
        rebuildTimer = nil
        rebuildDeadline = time.Time{}
    }
    rebuildMu.Unlock()
    w.WriteHeader(http.StatusOK)
}

func max(a, b int) int {
    if a > b {
        return a
    }
    return b
}
```

- [ ] **Schritt 6: Rebuild-Countdown in index.html**

Vor dem schließenden `</body>` Tag, Countdown-Leiste hinzufügen:

HTML (am Ende von `<body>`):
```html
<div id="rebuild-bar" style="display:none;position:fixed;bottom:0;left:0;right:0;
  background:#1a1a2e;border-top:1px solid #333;padding:0.6rem 1.5rem;
  display:flex;align-items:center;gap:1rem;font-size:0.8rem;color:#888;">
  <span>🔄 Rebuild in <strong id="rebuild-countdown">–</strong></span>
  <button onclick="rebuildNow()" style="background:#2979ff;color:#fff;border:none;
    padding:0.3rem 0.8rem;cursor:pointer;font-size:0.75rem;">Jetzt</button>
  <button onclick="rebuildCancel()" style="background:#333;color:#aaa;border:none;
    padding:0.3rem 0.8rem;cursor:pointer;font-size:0.75rem;">Abbrechen</button>
</div>
```

JavaScript (am Ende von `<script>`):
```javascript
function fmtSec(s) {
  const m = Math.floor(s / 60), r = s % 60;
  return m + ':' + String(r).padStart(2, '0');
}

async function pollRebuild() {
  try {
    const res = await fetch('/api/rebuild/status');
    const d = await res.json();
    const bar = document.getElementById('rebuild-bar');
    const cd = document.getElementById('rebuild-countdown');
    if (d.active) {
      bar.style.display = 'flex';
      cd.textContent = fmtSec(d.secondsRemaining);
    } else {
      bar.style.display = 'none';
    }
  } catch {}
}

async function rebuildNow() {
  await fetch('/api/rebuild/now', { method: 'POST' });
  document.getElementById('rebuild-bar').style.display = 'none';
}

async function rebuildCancel() {
  await fetch('/api/rebuild/cancel', { method: 'POST' });
  document.getElementById('rebuild-bar').style.display = 'none';
}

setInterval(pollRebuild, 5000);
pollRebuild();
```

- [ ] **Schritt 7: Build-Verifikation**

```bash
cd /etc/nixos && sudo nix build .#secrets-portal 2>&1 | tail -5
```
Erwartung: Kein Compile-Fehler.

- [ ] **Schritt 8: Commit**

```bash
cd /etc/nixos
sudo git add packages/secrets-portal/main.go packages/secrets-portal/static/index.html
sudo git commit -m "feat(secrets-portal): rebuild debounce timer (3 min) + countdown UI"
```

---

## Task 4: NixOS-Modul erweitern (2029-secrets-portal.nix)

**Files:**
- Modify: `modules/20-security/2029-secrets-portal.nix`

**Interfaces:**
- Consumes: profile.local.nix Pfad, Provision-Service-Name, Rebuild-Flake
- Produces: PROFILE_LOCAL_PATH, PROVISION_SERVICE, REBUILD_FLAKE in systemd Environment; profilePattern/profileType als Nix-Optionen

- [ ] **Schritt 1: secretDefType um profilePattern und profileType erweitern**

In `secretDefType`, nach der `validator` Option:
```nix
profilePattern = lib.mkOption {
  type = lib.types.str;
  default = "";
  description = ''
    Go-Regex mit einer Capture-Group für den Prefix. Matcht die Zeile in profile.local.nix
    die ersetzt werden soll. Leer = kein profile.local.nix Write für dieses Feld.
    Beispiel string: "(apiToken\\s*=\\s*\")[^\"]*\""
    Beispiel bool:   "(nixSubdomain\\s*=\\s*)(true|false)"
  '';
};

profileType = lib.mkOption {
  type = lib.types.enum [ "string" "bool" ];
  default = "string";
  description = "\"string\" schreibt Wert in Anführungszeichen; \"bool\" ohne.";
};
```

- [ ] **Schritt 2: Neue Modul-Optionen profileLocalPath, provisionService, rebuildFlake**

In `options.my.services.secrets-portal`, nach `secrets`:
```nix
profileLocalPath = lib.mkOption {
  type = lib.types.str;
  default = "/etc/nixos/machines/q958/profile.local.nix";
  description = "Pfad zu profile.local.nix für persistente Secret-Writes.";
};

provisionService = lib.mkOption {
  type = lib.types.str;
  default = "";
  description = "systemd-Service-Name der nach jedem Write neu gestartet wird (z.B. q958-secrets-provision).";
};

rebuildFlake = lib.mkOption {
  type = lib.types.str;
  default = "";
  description = "Flake-Referenz für nixos-rebuild switch (z.B. /etc/nixos#q958). Leer = kein auto-rebuild.";
};
```

- [ ] **Schritt 3: Environment und ReadWritePaths erweitern**

In `serviceConfig.Environment`, nach den bestehenden Einträgen:
```nix
Environment = [
  "LISTEN_ADDR=unix:${uds.secrets-portal}"
  "SECRETS_CONFIG=/etc/secrets-portal/secrets.json"
  "CRED_STORE=${config.my.creds.storeDir}"
  "SYSTEMD_CREDS_BIN=${pkgs.systemd}/bin/systemd-creds"
  "PROFILE_LOCAL_PATH=${cfg.profileLocalPath}"
  "PROVISION_SERVICE=${cfg.provisionService}"
  "REBUILD_FLAKE=${cfg.rebuildFlake}"
];
```

`ReadWritePaths` erweitern:
```nix
ReadWritePaths = [
  config.my.creds.storeDir
  (builtins.dirOf cfg.profileLocalPath)  # /etc/nixos/machines/q958/
];
```

- [ ] **Schritt 4: Dry-Build**

```bash
cd /etc/nixos && sudo bash scripts/nixos-rebuild-safe.sh 2>&1 | tail -10
```
Erwartung: `✓ Dry-build erfolgreich`

- [ ] **Schritt 5: Commit**

```bash
cd /etc/nixos
sudo git add modules/20-security/2029-secrets-portal.nix
sudo git commit -m "feat(secrets-portal): profilePattern/Type Options, PROFILE_LOCAL_PATH/PROVISION_SERVICE/REBUILD_FLAKE"
```

---

## Task 5: secrets-portal in services-spec.nix registrieren

**Files:**
- Modify: `lib/services-spec.nix`

**Interfaces:**
- Produces: Caddy-vHost `secrets.{domain}` (internal zone = LAN-only)

- [ ] **Schritt 1: Eintrag in mkDefaultSpec hinzufügen**

In `lib/services-spec.nix`, nach dem `grafana`-Eintrag (der ebenfalls einen socket verwendet):
```nix
secrets-portal = {
  socket = "/run/secrets-portal/secrets-portal.sock";
  zone = "internal";
  subdomain = "secrets";
  description = "Secrets Rotation Portal (LAN-only, write-only)";
};
```

- [ ] **Schritt 2: Dry-Build**

```bash
cd /etc/nixos && sudo bash scripts/nixos-rebuild-safe.sh 2>&1 | tail -10
```
Erwartung: `✓ Dry-build erfolgreich`

- [ ] **Schritt 3: Commit**

```bash
cd /etc/nixos
sudo git add lib/services-spec.nix
sudo git commit -m "feat(services-spec): secrets-portal (socket, internal zone, secrets subdomain)"
```

---

## Task 6: q958 konfigurieren und aktivieren

**Files:**
- Modify: `machines/q958/default.nix`
- Modify: `machines/q958/rollout.nix`

**Interfaces:**
- Consumes: my.services.secrets-portal Optionen aus Task 4
- Produces: Laufender secrets-portal Service auf `https://secrets.{domain}`

- [ ] **Schritt 1: secrets-portal in default.nix konfigurieren**

In `machines/q958/default.nix`, im `my = {` Block nach `creds.keys`:
```nix
services.secrets-portal = {
  enable = true;
  profileLocalPath = "/etc/nixos/machines/q958/profile.local.nix";
  provisionService = "q958-secrets-provision";
  rebuildFlake = "/etc/nixos#q958";
  secrets = [
    {
      name = "cloudflare_api_token";
      label = "Cloudflare API Token";
      description = "DDNS-Updater + ACME-Zertifikate (DNS-01). Braucht Zone.DNS.Edit für m7c5.de und moritzbaumeister.de.";
      link = "https://dash.cloudflare.com/profile/api-tokens";
      regex = "^[A-Za-z0-9_-]{32,}$";
      profilePattern = ''(apiToken\s*=\s*")[^"]*"'';
      validator = {
        url = "https://api.cloudflare.com/client/v4/user/tokens/verify";
        header = "Authorization";
        header_prefix = "Bearer ";
        expect_status = 200;
      };
    }
    {
      name = "domain_base";
      label = "Domain (Base)";
      description = "Basis-Domain z.B. moritzbaumeister.de oder m7c5.de. Nach Änderung: rebuild erforderlich.";
      regex = ''^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z]{2,})+$'';
      profilePattern = ''(base\s*=\s*")[^"]*"'';
    }
    {
      name = "domain_nix_subdomain";
      label = "nix. Subdomain";
      description = "true → service.nix.{base} | false → service.{base}. Nur ändern wenn kein Konflikt mit Unraid.";
      regex = ''^(true|false)$'';
      profilePattern = ''(nixSubdomain\s*=\s*)(true|false)'';
      profileType = "bool";
    }
    {
      name = "restic_repository";
      label = "Restic Repository (Koofr S3)";
      description = "Format: s3:s3.koofr.net/restic-q958/restic — Bucket vorher in Koofr anlegen.";
      link = "https://koofr.net/";
      regex = ''^s3:'';
      profilePattern = ''(repository\s*=\s*")[^"]*"'';
    }
    {
      name = "restic_aws_access_key_id";
      label = "Restic AWS Access Key ID";
      description = "Koofr S3 Access Key ID (Settings → S3 Access Keys).";
      link = "https://app.koofr.net/app/admin/preferences/password";
      regex = ''^[A-Za-z0-9]{16,}$'';
      profilePattern = ''(awsAccessKeyId\s*=\s*")[^"]*"'';
    }
    {
      name = "restic_aws_secret_access_key";
      label = "Restic AWS Secret Access Key";
      description = "Koofr S3 Secret Key.";
      regex = ''^[A-Za-z0-9+/]{16,}$'';
      profilePattern = ''(awsSecretAccessKey\s*=\s*")[^"]*"'';
    }
    {
      name = "privado_private_key";
      label = "PrivadoVPN WireGuard Key";
      description = "WireGuard PrivateKey (Base64, 44 Zeichen). Aus PrivadoVPN-Konfigdatei.";
      link = "https://privadovpn.com/";
      regex = ''^[A-Za-z0-9+/]{43}=$'';
      profilePattern = ''(privateKey\s*=\s*")[^"]*"'';
    }
    {
      name = "usenet_host";
      label = "Usenet Server Host";
      description = "z.B. news.usenetserver.com";
      regex = ''^[a-z0-9.-]+\.[a-z]{2,}$'';
      profilePattern = ''(host\s*=\s*")[^"]*"'';
      validator = {
        url = "tcp://\${value}:563";  # TCP-Connect — in Go speziell behandelt
        expect_status = 0;           # 0 = TCP-Connect ausreichend
      };
    }
    {
      name = "usenet_username";
      label = "Usenet Username";
      regex = ''^.{3,}$'';
      profilePattern = ''(username\s*=\s*")[^"]*"'';
    }
    {
      name = "usenet_password";
      label = "Usenet Passwort";
      regex = ''^.{6,}$'';
      profilePattern = ''(password\s*=\s*")[^"]*"'';
    }
    {
      name = "treasuremaps_api_key";
      label = "TreasureMaps API Key";
      description = "Indexer-Key für TreasureMaps.";
      link = "https://treasure-maps.com/";
      regex = ''^[a-zA-Z0-9]{16,}$'';
      profilePattern = ''(treasuremaps\.apiKey\s*=\s*")[^"]*"'';
      validator = {
        url = "https://treasure-maps.com/api/v1/indexer?apikey=\${value}";
        expect_status = 200;
      };
    }
  ];
};
```

**Hinweis zu usenet_host TCP-Validator:** Das `tcp://`-Schema erfordert eine Sonderbehandlung in `handleValidate()` (Task 7).

- [ ] **Schritt 2: secrets-portal in rollout.nix aktivieren**

In `machines/q958/rollout.nix`, nach den `my.core = {` Zeilen:
```nix
my.services.secrets-portal.enable = erstAb 1;
```

- [ ] **Schritt 3: creds.keys um secrets-portal-Schlüssel ergänzen**

In `machines/q958/default.nix`, `creds.keys` Liste ergänzen:
```nix
creds.keys = [
  "homeassistant_mqtt_password"
  "grafana_secret_key"
  "zigbee2mqtt.env"
  "pocket-id.env"
  "vaultwarden.env"
  "groq_api_key"
  "google_tts_api_key"
  # Secrets die das Portal schreibt:
  "cloudflare_api_token"
  "restic_repository"
  "restic_aws_access_key_id"
  "restic_aws_secret_access_key"
  "privado_private_key"
  "usenet_host"
  "usenet_username"
  "usenet_password"
  "treasuremaps_api_key"
];
```

- [ ] **Schritt 4: Dry-Build**

```bash
cd /etc/nixos && sudo bash scripts/nixos-rebuild-safe.sh 2>&1 | tail -10
```
Erwartung: `✓ Dry-build erfolgreich`

- [ ] **Schritt 5: Commit**

```bash
cd /etc/nixos
sudo git add machines/q958/default.nix machines/q958/rollout.nix
sudo git commit -m "feat(q958): secrets-portal aktivieren + vollständige secrets-Liste konfigurieren"
```

---

## Task 7: TCP-Validator für Usenet + nixos-rebuild switch

**Files:**
- Modify: `packages/secrets-portal/main.go`

**Interfaces:**
- Consumes: validator.url mit `tcp://host:port` Schema
- Produces: TCP-Connect als Validierungscheck statt HTTP

- [ ] **Schritt 1: TCP-Validator in handleValidate einbauen**

In `handleValidate()`, vor dem HTTP-Validator-Block:
```go
if def.Validator != nil && strings.HasPrefix(def.Validator.URL, "tcp://") {
    addr := strings.TrimPrefix(def.Validator.URL, "tcp://")
    conn, err := net.DialTimeout("tcp", addr, 8*time.Second)
    if err != nil {
        json.NewEncoder(w).Encode(validateResponse{Valid: false, Message: "Server nicht erreichbar"})
        return
    }
    conn.Close()
    json.NewEncoder(w).Encode(validateResponse{Valid: true, Message: "OK"})
    return
}
```

- [ ] **Schritt 2: nixos-rebuild braucht PATH**

In `runRebuild()`, den `exec.Command`-Aufruf ergänzen:
```go
cmd := exec.Command("nixos-rebuild", "switch", "--flake", rebuildFlake, "--impure")
cmd.Env = append(os.Environ(), "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin")
```

- [ ] **Schritt 3: Build und Dry-Build**

```bash
cd /etc/nixos && sudo nix build .#secrets-portal 2>&1 | tail -5
sudo bash scripts/nixos-rebuild-safe.sh 2>&1 | tail -10
```
Erwartung: Build und Dry-Build erfolgreich.

- [ ] **Schritt 4: nixos-rebuild switch**

```bash
cd /etc/nixos && sudo bash scripts/nixos-rebuild-safe.sh switch 2>&1 | tail -20
```
Erwartung: Switch erfolgreich, kein failed unit.

- [ ] **Schritt 5: Verifikation**

```bash
systemctl status secrets-portal
journalctl -u secrets-portal -n 20 --no-pager
curl --unix-socket /run/secrets-portal/secrets-portal.sock http://localhost/api/secrets | python3 -m json.tool | head -20
```
Erwartung: Service läuft, API gibt secrets-Liste zurück.

Portal im Browser öffnen: `https://secrets.{domain}` (oder direkte LAN-IP über Caddy).

- [ ] **Schritt 6: Commit**

```bash
cd /etc/nixos
sudo git add packages/secrets-portal/main.go
sudo git commit -m "feat(secrets-portal): TCP-Validator für Usenet, PATH für nixos-rebuild"
```
