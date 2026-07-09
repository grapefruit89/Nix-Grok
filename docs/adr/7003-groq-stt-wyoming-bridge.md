---
meta:
  role: doc
  purpose: ADR-7003 — STT via Groq Whisper + Wyoming Bridge statt lokalem Modell
  status: accepted
  date: 2026-07-09
  error_pattern: "AsrModel.*missing.*version|groq.stt.wyoming.*failed|CREDENTIALS_DIRECTORY not set"
  quick_fix: "sudo journalctl -u groq-stt-wyoming -n 30 --no-pager; sudo systemctl restart groq-stt-wyoming"
  services:
    - groq-stt-wyoming
  betrifft:
    - modules/70-home-automation/voice-assistant.nix
  docs:
    - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
    - docs/adr/2024-systemd-creds-tpm.md
  tags:
    - adr
    - home-automation
    - voice
    - stt
    - wyoming
    - groq
---

# ADR-7003: STT via Groq Whisper + Wyoming Bridge {#adr-7003}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-09 |
| **Host** | q958 |

---

## Kontext {#kontext}

- HA Assist braucht STT (Speech-to-Text) für die Voice-Pipeline
- q958 hat keinen ML-fähigen GPU (Intel i3-9100 + UHD 630) — lokale Whisper-Modelle (medium-int8) brauchen 8–12s pro Transkription, inakzeptabel für UX
- Deutschsprachige Erkennung ist Pflicht
- HACS-Extensions sind nicht deklarativ verwaltbar (kein `nixos-rebuild switch`)
- `openai_conversation` HA-Integration unterstützt **kein** `base_url` — Groq kann nicht direkt eingebunden werden (im HA-Quellcode `homeassistant/components/openai_conversation/__init__.py` bestätigt)
- `python313Packages.wyoming` ist in nixpkgs verfügbar → Wyoming-Bridge als NixOS-Service möglich

## Entscheidung {#entscheidung}

**Groq Whisper API via selbst geschriebener Wyoming-Bridge als systemd-Service.**

### Wyoming-Protokoll {#wyoming}

HA entdeckt STT-Services automatisch wenn sie das Wyoming-Protokoll auf TCP sprechen:

```
HA Assist → TCP 10300 → groq-stt-wyoming → Groq API → Transkript
```

Ablauf pro Transkription:
1. HA sendet `Describe` → Bridge antwortet `Info(asr=[AsrProgram(...)])`
2. HA sendet `Transcribe(language="de")`
3. HA sendet `AudioStart(rate=16000, width=2, channels=1)`
4. HA sendet `AudioChunk(audio=bytes)` × N
5. HA sendet `AudioStop`
6. Bridge baut WAV aus Chunks, POST an Groq API, gibt `Transcript(text=...)` zurück

### Groq API {#groq-api}

```
POST https://api.groq.com/openai/v1/audio/transcriptions
  model: whisper-large-v3-turbo
  language: de
  response_format: json
```

- Latenz: < 0.5s (Real-Time-Factor ~0.02)
- Free Tier: 7.200 Anfragen/Tag oder 2h Audio/Tag — kein Credit Card Billing bei Überschreitung (Hard Limit)
- API Key: versiegelt als `groq_api_key.cred` in `/var/lib/credstore.encrypted/` ([ADR-7001](7001-loadcredentialencrypted-vs-loadcredential.md))

### NixOS-Modul {#nixos-modul}

```nix
my.services.voice-assistant.enable = true;
# Port: 10300 (Wyoming Default)
# LoadCredentialEncrypted = groq_api_key.cred
```

Service: `modules/70-home-automation/voice-assistant.nix`

### Wyoming 1.9.0 — Breaking Change {#wyoming-breaking-change}

nixpkgs unstable enthält `python313Packages.wyoming` in Version **1.9.0** (nicht 1.8.0 wie dokumentiert).
In 1.9.0 ist `Artifact.version` ein **required** Feld (kein Default):

```python
# 1.8.0 — version optional mit Default
# 1.9.0 — PFLICHT, sonst TypeError:
# "AsrModel.__init__() missing 1 required positional argument: 'version'"

AsrModel(
    name="whisper-large-v3-turbo",
    description="...",
    attribution=Attribution(name="Groq", url="https://groq.com"),
    installed=True,
    version="1.0.0",   # ← in 1.9.0 explizit erforderlich
    languages=["de", "en"],
)
```

Gilt für `AsrModel` und `AsrProgram` gleichermaßen.

## Diagnose {#diagnose}

**Symptom:** HA zeigt keinen Wyoming STT-Provider in der Pipeline-Konfiguration, oder Service crasht.

```bash
sudo journalctl -u groq-stt-wyoming -n 30 --no-pager
```

**Wichtige Fehlermuster:**

| Fehler | Ursache | Fix |
|--------|---------|-----|
| `AsrModel.__init__() missing 1 required positional argument: 'version'` | wyoming 1.9.0 Breaking Change | `version="1.0.0"` in AsrModel/AsrProgram ergänzen |
| `CREDENTIALS_DIRECTORY not set` | LoadCredentialEncrypted fehlgeschlagen | `.cred`-Datei prüfen: `ls /var/lib/credstore.encrypted/groq_api_key.cred` |
| `groq_api_key missing in CREDENTIALS_DIRECTORY` | Credential-Name stimmt nicht | `sudo systemd-creds decrypt ... -` zum Prüfen |
| `403 Forbidden` von Groq API | API Key abgelaufen oder falsch | Key neu versiegeln ([ADR-7001](7001-loadcredentialencrypted-vs-loadcredential.md)) |

<details>
<summary>Vollständige Diagnose (ausklappen)</summary>

```bash
# Service-Status
sudo systemctl status groq-stt-wyoming --no-pager

# Port prüfen
sudo ss -tlnp | grep 10300

# Wyoming Handshake testen (braucht python mit wyoming)
PYTHON=$(sudo cat /proc/$(sudo systemctl show groq-stt-wyoming --property=MainPID --value)/cmdline | tr '\0' '\n' | head -1)
$PYTHON - << 'EOF'
import asyncio
from wyoming.client import AsyncTcpClient
from wyoming.info import Describe, Info

async def check():
    async with AsyncTcpClient("127.0.0.1", 10300) as c:
        await c.write_event(Describe().event())
        ev = await asyncio.wait_for(c.read_event(), timeout=5)
        if Info.is_type(ev.type):
            info = Info.from_event(ev)
            for p in info.asr:
                print(f"OK: {p.name}, models={[m.name for m in p.models]}")

asyncio.run(check())
EOF

# Groq API direkt testen
curl -s https://api.groq.com/openai/v1/models \
  -H "Authorization: Bearer $(sudo systemd-creds decrypt --name=groq_api_key /var/lib/credstore.encrypted/groq_api_key.cred -)" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('OK:', len(d['data']), 'Modelle')"
```

</details>

## Fix {#fix}

```bash
# 1. Service neu starten
sudo systemctl restart groq-stt-wyoming

# 2. Handshake prüfen (Wyoming Info-Response)
sudo systemctl status groq-stt-wyoming --no-pager
sudo ss -tlnp | grep 10300

# 3. Bei fehlendem API Key: neu versiegeln
printf '%s' 'gsk_...' | sudo systemd-creds encrypt --name=groq_api_key - \
  /var/lib/credstore.encrypted/groq_api_key.cred
sudo systemctl restart groq-stt-wyoming

# 4. Nach Code-Änderungen (voice-assistant.nix):
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure
```

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- < 0.5s Latenz vs. 8–12s lokal — für Sprach-UX entscheidend
- Vollständig deklarativ: `nixos-rebuild switch` bringt den Service
- Kein HACS, kein imperatives Setup
- Hard Limit im Free Tier: keine unerwarteten Abbuchungen
- Exzellente Deutsch-Erkennung (Whisper Large v3 Turbo)

### Negativ / Trade-offs {#negativ}

- Internet-Abhängigkeit: kein STT bei WAN-Ausfall
- Sprache geht an Groq-Server (Privacy-Trade-off für Voice Commands im Heimnetz)
- Free Tier: 7.200 Req/Tag oder 2h Audio — reicht für normalen Heimgebrauch locker

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Wyoming Bridge Service | `modules/70-home-automation/voice-assistant.nix` |
| NixOS Option | `my.services.voice-assistant.enable = true` |
| Modul-Import | `modules/70-home-automation/default.nix` |
| Aktivierung | `machines/q958/default.nix` |
| API Key | `/var/lib/credstore.encrypted/groq_api_key.cred` |

### Verifikation {#verifikation}

```bash
# Service aktiv?
sudo systemctl is-active groq-stt-wyoming

# Port offen?
sudo ss -tlnp | grep 10300
# → LISTEN 0.0.0.0:10300

# Wyoming Handshake OK?
# (Describe → Info mit AsrProgram groq-whisper)
sudo journalctl -u groq-stt-wyoming -n 5 --no-pager
# → Groq STT Wyoming bridge listening on port 10300
```

## Alternativen verworfen {#alternativen}

- **Lokales Whisper (faster-whisper NixOS-Modul)** — `services.wyoming.faster-whisper` ist in nixpkgs. Auf i3-9100 ohne GPU ~8–12s Latenz für medium-int8 Modell. Unakzeptabel für Voice UX. Abgelehnt.
- **`openai_conversation` Integration mit Groq** — Die HA-Integration besitzt kein `base_url`-Feld, Groq-Endpoint nicht konfigurierbar. Im Quellcode bestätigt. Abgelehnt.
- **HACS `extended_openai_conversation`** — Unterstützt `base_url`, kennt Groq. Nicht in nixpkgs, nicht deklarativ verwaltbar, bricht bei HA-Updates. Abgelehnt ([ADR-032](032-os-native-first.md)).
- **Piper TTS (lokale Sprachausgabe)** — Getestet: Deutsche Stimmen unzureichende Qualität für Alltagsnutzung. Abgelehnt für TTS-Rolle.
- **ElevenLabs** — Kein nennenswert großer Free Tier, HACS-Abhängigkeit. Abgelehnt.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-09 | Initial — Wyoming Bridge implementiert, wyoming 1.9.0 Breaking Change dokumentiert |

## Siehe auch {#siehe-auch}

- [ADR-7001 — LoadCredentialEncrypted](7001-loadcredentialencrypted-vs-loadcredential.md) — Credentials-Handling für den Groq API Key
- [ADR-7002 — HA .storage Provisioning](7002-ha-storage-provisioning.md) — Provisioning-Pattern für HA-Integrationen
- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — Credentials-Architektur
- [ADR-032 — OS-native-first](032-os-native-first.md) — warum HACS/HACS-Extensions abgelehnt werden
- [GUIDE-home-assistant.md](../guides/GUIDE-home-assistant.md) — kompletter HA-Stack Überblick
