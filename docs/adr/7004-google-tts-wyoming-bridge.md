---
meta:
  role: doc
  purpose: ADR-7004 — TTS via Google Cloud Text-to-Speech + Wyoming Bridge
  status: accepted
  date: 2026-07-09
  error_pattern: "google.tts.wyoming.*failed|CREDENTIALS_DIRECTORY not set|ConditionPathExists.*unmet"
  quick_fix: "sudo journalctl -u google-tts-wyoming -n 30 --no-pager; ls /var/lib/credstore.encrypted/google_tts_api_key.cred"
  services:
    - google-tts-wyoming
  betrifft:
    - modules/70-home-automation/voice-assistant.nix
  docs:
    - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
    - docs/adr/7003-groq-stt-wyoming-bridge.md
    - docs/adr/2024-systemd-creds-tpm.md
  tags:
    - adr
    - home-automation
    - voice
    - tts
    - wyoming
    - google-cloud
---

# ADR-7004: TTS via Google Cloud Text-to-Speech + Wyoming Bridge {#adr-7004}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-09 |
| **Host** | q958 |

---

## Kontext {#kontext}

- HA Assist braucht TTS (Text-to-Speech) für die Voice-Pipeline
- Lokale Lösung (Piper): Deutsche Stimmen haben unzureichende Qualität für Alltagsnutzung (getestet)
- ElevenLabs: kein relevanter Free Tier, erfordert HACS (nicht deklarativ)
- OpenAI TTS: akzeptable Qualität, aber zusätzliche API-Abhängigkeit wenn Groq bereits für STT läuft
- Google Cloud TTS: mehrere Qualitätsstufen (Chirp3-HD, Neural2, WaveNet), großzügige Free Tiers, API-Key-Auth ohne OAuth-Komplexität
- `python313Packages.wyoming` ist in nixpkgs verfügbar → Wyoming-Bridge als NixOS-Service möglich (gleicher Ansatz wie Groq STT, [ADR-7003](7003-groq-stt-wyoming-bridge.md))

## Entscheidung {#entscheidung}

**Google Cloud TTS via selbst geschriebener Wyoming-Bridge als systemd-Service auf Port 10200.**

### Wyoming-Protokoll {#wyoming}

HA Assist entdeckt TTS-Services automatisch wenn sie das Wyoming-Protokoll auf TCP sprechen:

```text
HA Assist → TCP 10200 → google-tts-wyoming → Google Cloud TTS API → PCM Audio
```

Ablauf pro Synthesize-Anfrage:
1. HA sendet `Describe` → Bridge antwortet `Info(tts=[TtsProgram(...)])`
2. HA sendet `Synthesize(text="...", voice=TtsVoiceName(...))`
3. Bridge POST an Google API, bekommt base64-encodiertes LINEAR16 PCM zurück
4. Bridge sendet `AudioStart(rate=24000, width=2, channels=1)`
5. Bridge sendet `AudioChunk(audio=bytes)` × N (je 4096 Bytes)
6. Bridge sendet `AudioStop`

### Google Cloud TTS API {#google-api}

```text
POST https://texttospeech.googleapis.com/v1/text:synthesize?key=<API_KEY>       # WaveNet, Neural2
POST https://texttospeech.googleapis.com/v1beta1/text:synthesize?key=<API_KEY>  # Chirp3-HD
```

- Auth: API Key im Query-Parameter (kein OAuth, kein Service Account)
- Response: `{"audioContent": "<base64>"}` — LINEAR16 PCM bei 24000 Hz
- Chirp3-HD erfordert **v1beta1** Endpoint, alle anderen Stimmen **v1**
- Stimmerkennung automatisch: `"Chirp3" in voice_name → v1beta1`

### Stimmqualität {#stimmen}

| Tier | Beispiel | Free Tier | Empfehlung |
|------|----------|-----------|------------|
| **Chirp3-HD** | `de-DE-Chirp3-HD-Aoede` | 1M Zeichen/Monat | Beste Qualität — empfohlen |
| **Neural2** | `de-DE-Neural2-A` | 1M Zeichen/Monat | Sehr gut |
| **WaveNet** | `de-DE-Wavenet-A` | 1M Zeichen/Monat | Gut |
| ~~Standard~~ | ~~`de-DE-Standard-A`~~ | ~~4M Zeichen/Monat~~ | Klingt wie Google Maps — ausgeschlossen |

Stimmvergleich vor der Auswahl: `bash ~/tts-test.sh` → `~/tts-samples/index.html`

### NixOS-Modul {#nixos-modul}

```nix
my.services.voice-assistant = {
  enable = true;      # Groq STT (Port 10300)
  tts.enable = true;  # Google TTS (Port 10200)
};
```text

Credentials via `profile.local.nix` (gitignored):
```nix
secrets.devKeys.googleTts = {
  apiKey = "AIza...";
  voice  = "de-DE-Chirp3-HD-Aoede";
};
```

Nach `nixos-rebuild switch` versiegelt `q958-secrets-provision` den API Key automatisch als
`/var/lib/credstore.encrypted/google_tts_api_key.cred`.

Service: `modules/70-home-automation/voice-assistant.nix`

### Wyoming 1.9.0 — Breaking Change {#wyoming-breaking-change}

Gleiche Problematik wie bei ADR-7003 ([→ Details](7003-groq-stt-wyoming-bridge.md#wyoming-breaking-change)):
`Artifact.version` ist in wyoming 1.9.0 ein **required** Feld. Gilt auch für TTS-Klassen:

```python
# PFLICHT in wyoming 1.9.0: {#pflicht-in-wyoming-190}
TtsVoice(name="...", ..., version="1.0.0")    # ohne version= → TypeError
TtsProgram(name="...", ..., version="1.0.0")  # ohne version= → TypeError
```bash

### Graceful Start ohne Credentials {#condition}

Der Service startet nur wenn der API Key bereits versiegelt vorliegt:

```nix
unitConfig.ConditionPathExists =
  "/var/lib/credstore.encrypted/google_tts_api_key.cred";
```

Ohne Credentials: `inactive (dead)` mit `Condition: start condition unmet` — kein Fehler, kein Restart-Loop.
Nach Credential-Setup und `nixos-rebuild switch`: Service startet automatisch.

## Preismodell {#preismodell}

Google Cloud TTS hat **getrennte Free-Tier-Kontingente** pro Stimmqualität:

| Stimmtyp | Monatlich gratis | Danach |
|----------|-----------------|--------|
| Standard | 4.000.000 Zeichen | $4/1M |
| WaveNet | 1.000.000 Zeichen | $16/1M |
| Neural2 | 1.000.000 Zeichen | $16/1M |
| Chirp3-HD | 1.000.000 Zeichen | ~$30/1M |

**Wichtig:** WaveNet- und Neural2-Kontingent sind voneinander unabhängig — eine Stimme nach der
anderen zu nutzen würde das kombinierte Free Tier verdoppeln. In der Praxis ist das irrelevant:

> **Realistische HA-Nutzung:**  
> 20 Ansagen/Tag × 100 Zeichen = 2.000 Zeichen/Tag = **~500 Tage bis zur Grenze**  
> 1.000.000 Zeichen Free Tier ≈ 50 Jahre normaler HA-Betrieb

**Der Free Tier wird nie ausgeschöpft.** Der Circuit Breaker (s.u.) ist dennoch Pflicht — nicht
wegen normaler Nutzung, sondern als Schutz gegen API-Key-Leaks.

### Circuit Breaker — €0-Budget {#circuit-breaker}

**Pflichtschritt nach GCP-Projekt-Erstellung:**

1. GCP Console → Abrechnung → Budgets und Benachrichtigungen → Budget erstellen
2. Budget: €0 (oder €1 als Puffer)
3. Aktion bei 100%: **Abrechnung deaktivieren** (nicht nur Benachrichtigung!)

→ Bei API-Key-Leak werden maximal die Free-Tier-Anfragen pro Monat verbraucht, danach blockiert GCP.

## Diagnose {#diagnose}

```bash
# Service-Status {#service-status}
sudo systemctl status google-tts-wyoming --no-pager

# Service wartet auf Credentials (kein Fehler — expected) {#service-wartet-auf-credentials-kein-fehler-expected}
sudo systemctl status google-tts-wyoming | grep -E "Condition|inactive"
# → Condition: start condition unmet → erst nach nixos-rebuild switch mit Credentials {#condition-start-condition-unmet-erst-nach-nixos-rebuild-switch-mit-credentials}

# Port prüfen (wenn aktiv) {#port-pruefen-wenn-aktiv}
sudo ss -tlnp | grep 10200
```bash

**Fehlermuster:**

| Symptom | Ursache | Fix |
|---------|---------|-----|
| `inactive (dead)` + `Condition unmet` | `.cred`-Datei fehlt noch | Credentials in `profile.local.nix` eintragen, rebuild |
| `CREDENTIALS_DIRECTORY not set` | `LoadCredentialEncrypted` fehlgeschlagen | `.cred`-Datei prüfen: `ls /var/lib/credstore.encrypted/google_tts_api_key.cred` |
| `GOOGLE_TTS_VOICE not set` | `google-tts.env` fehlt | `ls /var/lib/secrets/google-tts.env` |
| `TtsVoice.__init__() missing 1 required positional argument: 'version'` | wyoming 1.9.0 Breaking Change | `version="1.0.0"` in TtsVoice/TtsProgram |
| `400 Bad Request` von Google API | Chirp3-HD mit v1 Endpoint | Bridge erkennt automatisch: `"Chirp3" in voice → v1beta1` |
| `403 Forbidden` von Google API | API Key falsch oder TTS API nicht aktiviert | GCP Console → APIs → Cloud Text-to-Speech API prüfen |

<details>
<summary>Vollständige Diagnose (ausklappen)</summary>

```bash
# Alle Voice-Services auf einen Blick {#alle-voice-services-auf-einen-blick}
sudo systemctl status groq-stt-wyoming google-tts-wyoming --no-pager

# Port-Check beider Bridges {#port-check-beider-bridges}
sudo ss -tlnp | grep -E "10200|10300"

# Credential-Dateien prüfen {#credential-dateien-pruefen}
ls -la /var/lib/credstore.encrypted/google_tts_api_key.cred
ls -la /var/lib/secrets/google-tts.env

# Voice-Datei zeigen (nur Voice-Name, kein Key) {#voice-datei-zeigen-nur-voice-name-kein-key}
sudo cat /var/lib/secrets/google-tts.env

# Google TTS API direkt testen {#google-tts-api-direkt-testen}
KEY=$(sudo systemd-creds decrypt --name=google_tts_api_key \
  /var/lib/credstore.encrypted/google_tts_api_key.cred -)
curl -sf "https://texttospeech.googleapis.com/v1/voices?languageCode=de-DE&key=$KEY" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('OK:', len(d['voices']), 'Stimmen')"
```

</details>

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Natürliche Sprachqualität (Chirp3-HD) — deutlich besser als Piper lokal
- Free Tier reicht für HA-Nutzung auf Jahrzehnte
- Vollständig deklarativ: `nixos-rebuild switch` bringt den Service
- Kein OAuth / Service Account — API Key reicht
- Circuit Breaker (€0-Budget) verhindert unerwartete Abbuchungen auch bei Key-Leak
- Graceful Start: kein Fehler wenn Credentials noch nicht gesetzt

### Negativ / Trade-offs {#negativ}

- Internet-Abhängigkeit: kein TTS bei WAN-Ausfall
- TTS-Text geht an Google-Server (Privacy-Trade-off)
- Chirp3-HD erfordert v1beta1 Endpoint (experimentell, kann sich ändern)

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Wyoming Bridge Service | `modules/70-home-automation/voice-assistant.nix` |
| NixOS Option | `my.services.voice-assistant.tts.enable = true` |
| Credential-Provisioning | `machines/q958/secrets.nix` |
| Aktivierung | `machines/q958/default.nix` |
| API Key (verschlüsselt) | `/var/lib/credstore.encrypted/google_tts_api_key.cred` |
| Voice-Name Env | `/var/lib/secrets/google-tts.env` |
| Stimmvergleich-Tool | `~/tts-test.sh` |

### Verifikation {#verifikation}

```bash
# Service aktiv? {#service-aktiv}
sudo systemctl is-active google-tts-wyoming

# Port offen? {#port-offen}
sudo ss -tlnp | grep 10200
# → LISTEN 0.0.0.0:10200 {#listen-000010200}

# Log-Check {#log-check}
sudo journalctl -u google-tts-wyoming -n 5 --no-pager
# → Google TTS Wyoming bridge on port 10200 (voice: de-DE-Chirp3-HD-Aoede) {#google-tts-wyoming-bridge-on-port-10200-voice-de-de-chirp3-hd-aoede}
```nix

## Alternativen verworfen {#alternativen}

- **Piper (lokal)** — `services.wyoming.piper` in nixpkgs. Deutsche Stimmen nach Test unzureichend für Alltagsnutzung. Abgelehnt.
- **OpenAI TTS** — Gute Qualität, spricht Deutsch. Aber: weitere API-Abhängigkeit, kein klarer Free Tier für TTS, und OpenAI hat kein €0-Budget-Circuit-Breaker-Äquivalent. Abgelehnt.
- **ElevenLabs** — Sehr gute Qualität, aber kein relevanter Free Tier und erfordert HACS ([ADR-032](032-os-native-first.md)). Abgelehnt.
- **Azure TTS** — Ähnlicher Ansatz wie Google, aber kleinerer Free Tier (500k Zeichen). Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-09 | Initial — Google Cloud TTS Wyoming Bridge implementiert; Preismodell (getrennte Free-Tier-Töpfe) dokumentiert |

## Siehe auch {#siehe-auch}

- [ADR-7003 — Groq STT Wyoming Bridge](7003-groq-stt-wyoming-bridge.md) — STT-Gegenstück; Wyoming-Protokoll und wyoming 1.9.0 Breaking Change
- [ADR-7001 — LoadCredentialEncrypted](7001-loadcredentialencrypted-vs-loadcredential.md) — Credentials-Handling für den Google TTS API Key
- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — Credentials-Architektur
- [ADR-032 — OS-native-first](032-os-native-first.md) — warum HACS/ElevenLabs abgelehnt werden
- [GUIDE-home-assistant.md](../guides/GUIDE-home-assistant.md) — kompletter HA-Stack Überblick
