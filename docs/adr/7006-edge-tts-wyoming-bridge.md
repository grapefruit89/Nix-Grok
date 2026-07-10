---
meta:
  role: doc
  purpose: ADR-7006 — TTS via Microsoft Edge TTS + Wyoming Bridge (kein API Key)
  status: accepted
  date: 2026-07-10
  error_pattern: "Edge TTS error:|edge.tts.wyoming.*failed"
  quick_fix: "sudo journalctl -u edge-tts-wyoming -n 30 --no-pager; sudo systemctl restart edge-tts-wyoming"
  services:
    - edge-tts-wyoming
  betrifft:
    - modules/70-home-automation/voice-assistant.nix
  docs:
    - docs/adr/7004-google-tts-wyoming-bridge.md
    - docs/adr/7003-groq-stt-wyoming-bridge.md
  tags:
    - adr
    - home-automation
    - voice
    - tts
    - wyoming
    - edge-tts
    - microsoft
---

# ADR-7006: TTS via Microsoft Edge TTS + Wyoming Bridge {#adr-7006}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-10 |
| **Host** | q958 |

---

## Kontext {#kontext}

- Bereits implementiert: Google Cloud TTS Wyoming Bridge (Port 10200, [ADR-7004](7004-google-tts-wyoming-bridge.md)) — wartet noch auf API Key Setup
- Gesucht: zweite TTS-Option die **sofort funktioniert**, ohne Konsolenzugang, ohne API Key
- Budget: 0 € — keine bezahlten Services
- Hardware: i3-9100 (Coffee Lake) + 32 GB RAM — lokale ML-Modelle (Kokoro 82M, 1,5 GB RAM) zu schwergewichtig für dauerhaften Betrieb
- Qualitätsanforderung: besser als Piper (getestet — unzureichende deutsche Intonation)

**Entscheidung gegen lokale TTS-Modelle** (Kokoro, Piper, XTTS):
- Kokoro 82M: 1,5 GB RAM dauerhaft, ~500ms Latenz für kurzen Satz — zu viel Overhead für Homelab
- Piper: beste lokale Option, aber Qualität nach Test unzureichend ([ADR-7003 — Alternativen verworfen](7003-groq-stt-wyoming-bridge.md#alternativen))
- XTTS-v2, Fish Speech: viel zu schwer für i7-7500U/i3-9100 ohne dedizierter GPU

**Microsoft Edge TTS** (`edge-tts` Python-Paket) nutzt denselben Dienst wie der
Microsoft Edge Browser für seine eingebettete TTS-Funktion. Kein Account, kein API Key,
kein Rate Limit. Das Paket spricht die interne Microsoft-API direkt an.

## Entscheidung {#entscheidung}

**Microsoft Edge TTS via selbst geschriebener Wyoming-Bridge als systemd-Service auf Port 10201.**

Beide TTS-Services laufen parallel — HA kann beliebig zwischen ihnen wählen:

```
Port 10200 → google-tts-wyoming → Google Cloud TTS (API Key erforderlich)
Port 10201 → edge-tts-wyoming   → Microsoft Edge TTS (kein API Key)
```

### Wyoming-Protokoll {#wyoming}

Identisch mit Google TTS Bridge ([ADR-7004](7004-google-tts-wyoming-bridge.md#wyoming)):

```
HA Assist → TCP 10201 → edge-tts-wyoming → Microsoft Edge TTS API → MP3 → ffmpeg → PCM
```

Ablauf pro Synthesize-Anfrage:
1. HA sendet `Describe` → Bridge antwortet `Info(tts=[TtsProgram(...)])`
2. HA sendet `Synthesize(text="...")`
3. Bridge streamt MP3-Chunks von Microsoft Edge TTS API
4. ffmpeg konvertiert MP3 → PCM s16le 24000 Hz mono
5. Bridge sendet `AudioStart(rate=24000, width=2, channels=1)`
6. Bridge sendet `AudioChunk(audio=bytes)` × N
7. Bridge sendet `AudioStop`

### Audio-Pipeline {#audio}

Edge TTS gibt MP3 aus (24kHz, mono). Wyoming erwartet PCM (raw bytes). Konvertierung:

```
edge-tts.Communicate.stream()  →  MP3-Chunks  →  asyncio.create_subprocess_exec(ffmpeg)
  -i pipe:0  -f s16le  -ar 24000  -ac 1  pipe:1
→  signed 16-bit little-endian PCM
```

ffmpeg-Pfad ist im Nix-Store hardcodiert (`${pkgs.ffmpeg}/bin/ffmpeg`) — kein PATH-Lookup.

### Deutsche Stimmen {#stimmen}

| Stimme | Charakter |
|--------|-----------|
| `de-DE-KatjaNeural` | Weiblich, natürlich, klar — **Standard** |
| `de-DE-ConradNeural` | Männlich, professionell |
| `de-DE-AmalaNeural` | Weiblich, warm |
| `de-AT-IngridNeural` | Österreichisch, weiblich |
| `de-CH-LeniNeural` | Schweizerdeutsch, weiblich |

Alle verfügbaren Stimmen abrufen:
```bash
python3 -c "import asyncio, edge_tts; asyncio.run(edge_tts.list_voices())" | python3 -c "
import json, sys
for v in json.load(sys.stdin):
    if v['Locale'].startswith('de-'):
        print(v['ShortName'], v['Gender'])
"
```

### NixOS-Modul {#nixos-modul}

```nix
my.services.voice-assistant = {
  enable = true;           # Groq STT (Port 10300)
  tts.enable = true;       # Google TTS (Port 10200)
  edgeTts.enable = true;   # Edge TTS  (Port 10201) — dieser ADR
};
```

Optionen:
```nix
my.services.voice-assistant.edgeTts = {
  enable  = true;                 # default: false
  port    = 10201;                # default: 10201
  voice   = "de-DE-KatjaNeural"; # default: de-DE-KatjaNeural
};
```

Keine Credential-Datei nötig — kein `ConditionPathExists`, kein `LoadCredentialEncrypted`.
Service startet sofort nach `nixos-rebuild switch`.

## Diagnose {#diagnose}

```bash
# Service-Status
sudo systemctl status edge-tts-wyoming --no-pager

# Port prüfen
sudo ss -tlnp | grep 10201

# Log (sollte "Edge TTS Wyoming bridge on port 10201" zeigen)
sudo journalctl -u edge-tts-wyoming -n 10 --no-pager
```

**Fehlermuster:**

| Symptom | Ursache | Fix |
|---------|---------|-----|
| `Edge TTS error: ...` | Microsoft-API nicht erreichbar | WAN-Verbindung prüfen: `curl -sI https://speech.microsoft.com` |
| `ModuleNotFoundError: edge_tts` | edgePython-Env falsch | `sudo nixos-rebuild switch` |
| `edge-tts-wyoming inactive` | Service nicht enabled | `edgeTts.enable = true` in `default.nix` |
| HA zeigt Edge TTS nicht | Wyoming nicht hinzugefügt | HA → Einstellungen → Integrationen → Wyoming → Port 10201 |

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}

- Startet sofort — kein API-Key-Setup nötig
- Kostenlos, kein Account, kein Rate Limit
- Sehr gute deutsche Sprachqualität (Neural, flüssig)
- 39 MB RAM (Python + edge-tts-Paket) — minimal
- Läuft parallel zu Google TTS — beide verfügbar in HA
- Fallback wenn Google TTS API Key noch nicht gesetzt

### Negativ / Trade-offs {#negativ}

- Internet-Abhängigkeit: kein TTS bei WAN-Ausfall
- TTS-Text geht an Microsoft-Server (Privacy-Trade-off, gleich wie Google)
- Inoffizielle API — könnte sich ohne Ankündigung ändern (seit Jahren stabil)
- MP3-Zwischenstufe (Microsoft-Output) erfordert ffmpeg als Dependency

### Implementierung {#implementierung}

| Artefakt | Pfad |
|----------|------|
| Wyoming Bridge Service | `modules/70-home-automation/voice-assistant.nix` |
| NixOS Option | `my.services.voice-assistant.edgeTts.enable = true` |
| Aktivierung | `machines/q958/default.nix` |
| Python-Umgebung | `edgePython = pkgs.python3.withPackages (ps: [ ps.wyoming ps.edge-tts ])` |
| ffmpeg (MP3→PCM) | `${pkgs.ffmpeg}/bin/ffmpeg` (Nix-Store-Pfad, hardcodiert) |

### Verifikation {#verifikation}

```bash
# Service aktiv?
sudo systemctl is-active edge-tts-wyoming
# → active

# Port offen?
sudo ss -tlnp | grep 10201
# → LISTEN 0.0.0.0:10201

# Log-Check
sudo journalctl -u edge-tts-wyoming -n 3 --no-pager
# → Edge TTS Wyoming bridge on port 10201 (voice: de-DE-KatjaNeural)
```

## Alternativen verworfen {#alternativen}

- **Piper (lokal, nixpkgs: `services.wyoming.piper`)** — Deutsche Stimmen nach Test unzureichend. Abgelehnt.
- **Kokoro 82M (lokal)** — 1,5 GB RAM dauerhaft; zu schwer für q958-Alltagsbetrieb. Abgelehnt.
- **OpenAI TTS** — Weitere API-Abhängigkeit ohne Clear Free Tier für TTS. Kein €0-Budget-Äquivalent. Abgelehnt.
- **Google Cloud TTS** — Wird parallel betrieben ([ADR-7004](7004-google-tts-wyoming-bridge.md)); braucht API Key Setup.
- **Fish Speech / XTTS-v2** — Zu schwer für CPU-only-Betrieb auf i3-9100. Abgelehnt.
- **`wyoming-opentts`** — Würde edge-tts wrappen, aber als Container-Lösung. Nicht nötig da direktes Python-Paket verfügbar.

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-10 | Initial — Edge TTS Wyoming Bridge implementiert; läuft parallel zu Google TTS |

## Siehe auch {#siehe-auch}

- [ADR-7004 — Google Cloud TTS Wyoming Bridge](7004-google-tts-wyoming-bridge.md) — das andere TTS; läuft parallel auf Port 10200
- [ADR-7003 — Groq STT Wyoming Bridge](7003-groq-stt-wyoming-bridge.md) — STT-Gegenstück
- [GUIDE-home-assistant.md](../guides/GUIDE-home-assistant.md) — kompletter HA-Stack Überblick
