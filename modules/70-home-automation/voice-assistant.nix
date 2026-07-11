# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Voice Assistant — Groq STT + Google Cloud TTS (Wyoming Bridges)
#   services:
#     - groq-stt-wyoming
#     - google-tts-wyoming
#   tags:
#     - iot
#     - home-automation
#     - voice
#     - stt
#     - tts
#   docs:
#     - docs/adr/7003-groq-stt-wyoming-bridge.md
#     - docs/adr/7001-loadcredentialencrypted-vs-loadcredential.md
#     - docs/guides/GUIDE-home-assistant.md
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.voice-assistant;
  python = pkgs.python3.withPackages (ps: [ ps.wyoming ]);
  edgePython = pkgs.python3.withPackages (ps: [
    ps.wyoming
    ps.edge-tts
  ]);

  # ─── STT: Groq Whisper ───────────────────────────────────────────────────
  groqSttBridge = pkgs.writeScript "groq-stt-bridge" ''
    #!${python}/bin/python3
    """Groq Whisper STT Wyoming bridge."""
    import asyncio, io, json, os, sys, wave, urllib.request
    from pathlib import Path
    from wyoming.asr import Transcript
    from wyoming.audio import AudioChunk, AudioStart, AudioStop
    from wyoming.event import Event
    from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
    from wyoming.server import AsyncEventHandler, AsyncServer

    GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
    MODEL    = "${cfg.model}"
    LANGUAGE = "${cfg.language}"
    PORT     = ${toString cfg.port}

    def _transcribe(wav: bytes, key: str) -> str:
        bd = b"----GroqBridge"
        body = (
            b"--" + bd + b"\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
            + wav
            + b"\r\n--" + bd + b"\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n" + MODEL.encode()
            + b"\r\n--" + bd + b"\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n" + LANGUAGE.encode()
            + b"\r\n--" + bd + b"\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson"
            + b"\r\n--" + bd + b"--\r\n"
        )
        req = urllib.request.Request(GROQ_URL, data=body,
            headers={"Authorization": f"Bearer {key}", "Content-Type": f"multipart/form-data; boundary={bd.decode()}"},
            method="POST")
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read()).get("text", "")

    class SttHandler(AsyncEventHandler):
        def __init__(self, api_key, *a, **kw):
            super().__init__(*a, **kw)
            self._key = api_key
            self._chunks: list[AudioChunk] = []
            self._rate, self._width, self._channels = 16000, 2, 1

        async def handle_event(self, event: Event) -> bool:
            if Describe.is_type(event.type):
                await self.write_event(Info(asr=[AsrProgram(
                    name="groq-whisper", description="Groq Whisper Large v3 Turbo",
                    attribution=Attribution(name="Groq", url="https://groq.com"),
                    installed=True, version="1.0.0",
                    models=[AsrModel(
                        name="whisper-large-v3-turbo",
                        description="Groq Whisper Large v3 Turbo (Deutsch)",
                        attribution=Attribution(name="Groq", url="https://groq.com"),
                        installed=True, version="1.0.0", languages=["de", "en"],
                    )],
                )]).event())
                return True
            if AudioStart.is_type(event.type):
                s = AudioStart.from_event(event)
                self._rate, self._width, self._channels = s.rate, s.width, s.channels
                self._chunks = []
                return True
            if AudioChunk.is_type(event.type):
                self._chunks.append(AudioChunk.from_event(event))
                return True
            if AudioStop.is_type(event.type):
                text = ""
                if self._chunks:
                    buf = io.BytesIO()
                    with wave.open(buf, "wb") as wf:
                        wf.setnchannels(self._channels); wf.setsampwidth(self._width); wf.setframerate(self._rate)
                        for c in self._chunks: wf.writeframes(c.audio)
                    try:
                        text = await asyncio.get_event_loop().run_in_executor(None, _transcribe, buf.getvalue(), self._key)
                    except Exception as e:
                        print(f"Groq error: {e}", file=sys.stderr)
                await self.write_event(Transcript(text=text).event())
                return True
            return True

    async def main():
        creds = os.environ.get("CREDENTIALS_DIRECTORY")
        if not creds: print("CREDENTIALS_DIRECTORY not set", file=sys.stderr); sys.exit(1)
        kf = Path(creds) / "groq_api_key"
        if not kf.exists(): print("groq_api_key missing", file=sys.stderr); sys.exit(1)
        key = kf.read_text().strip()
        server = AsyncServer.from_uri(f"tcp://0.0.0.0:{PORT}")
        print(f"Groq STT Wyoming bridge on port {PORT}", flush=True)
        await server.run(lambda *a, **kw: SttHandler(key, *a, **kw))

    asyncio.run(main())
  '';

  # ─── TTS: Google Cloud Text-to-Speech ────────────────────────────────────
  googleTtsBridge = pkgs.writeScript "google-tts-bridge" ''
    #!${python}/bin/python3
    """Google Cloud TTS Wyoming bridge."""
    import asyncio, base64, json, os, sys, urllib.request
    from pathlib import Path
    from wyoming.audio import AudioChunk, AudioStart, AudioStop
    from wyoming.event import Event
    from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
    from wyoming.server import AsyncEventHandler, AsyncServer
    from wyoming.tts import Synthesize

    PORT       = ${toString cfg.tts.port}
    SAMPLE_RATE = 24000   # Hz — Google TTS LINEAR16 output
    CHUNK_SIZE  = 4096    # bytes per AudioChunk

    def _synthesize(text: str, voice: str, key: str) -> bytes:
        # Chirp3-HD benötigt v1beta1, alle anderen v1
        api = "v1beta1" if "Chirp3" in voice else "v1"
        url = f"https://texttospeech.googleapis.com/{api}/text:synthesize?key={key}"
        lang = "-".join(voice.split("-")[:2])   # "de-DE-Chirp3-HD-Aoede" → "de-DE"
        payload = json.dumps({
            "input": {"text": text},
            "voice": {"languageCode": lang, "name": voice},
            "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": SAMPLE_RATE},
        }).encode()
        req = urllib.request.Request(url, data=payload,
            headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as r:
            return base64.b64decode(json.loads(r.read())["audioContent"])

    class TtsHandler(AsyncEventHandler):
        def __init__(self, api_key, voice, *a, **kw):
            super().__init__(*a, **kw)
            self._key   = api_key
            self._voice = voice

        async def handle_event(self, event: Event) -> bool:
            if Describe.is_type(event.type):
                lang = "-".join(self._voice.split("-")[:2])
                await self.write_event(Info(tts=[TtsProgram(
                    name="google-tts",
                    description="Google Cloud Text-to-Speech",
                    attribution=Attribution(name="Google", url="https://cloud.google.com/text-to-speech"),
                    installed=True, version="1.0.0",
                    voices=[TtsVoice(
                        name=self._voice,
                        description=f"Google TTS {self._voice}",
                        attribution=Attribution(name="Google", url="https://cloud.google.com"),
                        installed=True, version="1.0.0",
                        languages=[lang.lower().replace("-", "_")],
                    )],
                )]).event())
                return True

            if Synthesize.is_type(event.type):
                req = Synthesize.from_event(event)
                try:
                    pcm = await asyncio.get_event_loop().run_in_executor(
                        None, _synthesize, req.text, self._voice, self._key)
                except Exception as e:
                    print(f"Google TTS error: {e}", file=sys.stderr)
                    pcm = b""
                await self.write_event(AudioStart(rate=SAMPLE_RATE, width=2, channels=1).event())
                for i in range(0, max(len(pcm), 1), CHUNK_SIZE):
                    await self.write_event(AudioChunk(
                        rate=SAMPLE_RATE, width=2, channels=1,
                        audio=pcm[i:i+CHUNK_SIZE]).event())
                await self.write_event(AudioStop().event())
                return True

            return True

    async def main():
        creds = os.environ.get("CREDENTIALS_DIRECTORY")
        if not creds: print("CREDENTIALS_DIRECTORY not set", file=sys.stderr); sys.exit(1)
        kf = Path(creds) / "google_tts_api_key"
        if not kf.exists(): print("google_tts_api_key missing", file=sys.stderr); sys.exit(1)
        key   = kf.read_text().strip()
        voice = os.environ.get("GOOGLE_TTS_VOICE", "")
        if not voice: print("GOOGLE_TTS_VOICE not set", file=sys.stderr); sys.exit(1)
        server = AsyncServer.from_uri(f"tcp://0.0.0.0:{PORT}")
        print(f"Google TTS Wyoming bridge on port {PORT} (voice: {voice})", flush=True)
        await server.run(lambda *a, **kw: TtsHandler(key, voice, *a, **kw))

    asyncio.run(main())
  '';

  # ─── TTS: Microsoft Edge TTS ─────────────────────────────────────────────
  edgeTtsBridge = pkgs.writeScript "edge-tts-bridge" ''
    #!${edgePython}/bin/python3
    """Microsoft Edge TTS Wyoming bridge (kein API Key)."""
    import asyncio, sys, os
    from wyoming.audio import AudioChunk, AudioStart, AudioStop
    from wyoming.event import Event
    from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
    from wyoming.server import AsyncEventHandler, AsyncServer
    from wyoming.tts import Synthesize
    import edge_tts

    PORT        = ${toString cfg.edgeTts.port}
    SAMPLE_RATE = 24000
    CHUNK_SIZE  = 4096

    async def _synthesize(text: str, voice: str) -> bytes:
        communicate = edge_tts.Communicate(text, voice)
        mp3 = b"".join(
            c["data"] async for c in communicate.stream() if c["type"] == "audio"
        )
        proc = await asyncio.create_subprocess_exec(
            "${pkgs.ffmpeg}/bin/ffmpeg",
            "-i", "pipe:0", "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", "1", "pipe:1",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        pcm, _ = await proc.communicate(mp3)
        return pcm

    class TtsHandler(AsyncEventHandler):
        def __init__(self, voice, *a, **kw):
            super().__init__(*a, **kw)
            self._voice = voice

        async def handle_event(self, event: Event) -> bool:
            if Describe.is_type(event.type):
                lang = self._voice[:5].lower().replace("-", "_")
                await self.write_event(Info(tts=[TtsProgram(
                    name="edge-tts",
                    description="Microsoft Edge Text-to-Speech",
                    attribution=Attribution(name="Microsoft", url="https://azure.microsoft.com"),
                    installed=True, version="1.0.0",
                    voices=[TtsVoice(
                        name=self._voice,
                        description=f"Edge TTS {self._voice}",
                        attribution=Attribution(name="Microsoft", url="https://azure.microsoft.com"),
                        installed=True, version="1.0.0",
                        languages=[lang],
                    )],
                )]).event())
                return True

            if Synthesize.is_type(event.type):
                req = Synthesize.from_event(event)
                try:
                    pcm = await _synthesize(req.text, self._voice)
                except Exception as e:
                    print(f"Edge TTS error: {e}", file=sys.stderr)
                    pcm = b""
                await self.write_event(AudioStart(rate=SAMPLE_RATE, width=2, channels=1).event())
                for i in range(0, max(len(pcm), 1), CHUNK_SIZE):
                    await self.write_event(AudioChunk(
                        rate=SAMPLE_RATE, width=2, channels=1,
                        audio=pcm[i:i+CHUNK_SIZE]).event())
                await self.write_event(AudioStop().event())
                return True

            return True

    async def main():
        voice = os.environ.get("EDGE_TTS_VOICE", "${cfg.edgeTts.voice}")
        server = AsyncServer.from_uri(f"tcp://0.0.0.0:{PORT}")
        print(f"Edge TTS Wyoming bridge on port {PORT} (voice: {voice})", flush=True)
        await server.run(lambda *a, **kw: TtsHandler(voice, *a, **kw))

    asyncio.run(main())
  '';
in
{
  options.my.services.voice-assistant = {
    enable = lib.mkEnableOption "Voice Assistant (Groq STT Wyoming bridge)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 10300;
      description = "Wyoming STT port.";
    };
    language = lib.mkOption {
      type = lib.types.str;
      default = "de";
      description = "BCP-47 Sprache für Groq Whisper STT (z. B. de, en, fr).";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "whisper-large-v3-turbo";
      description = "Groq Whisper-Modell-ID.";
    };
    tts = {
      enable = lib.mkEnableOption "Google Cloud TTS Wyoming bridge";
      port = lib.mkOption {
        type = lib.types.port;
        default = 10200;
        description = "Wyoming TTS port.";
      };
    };
    edgeTts = {
      enable = lib.mkEnableOption "Microsoft Edge TTS Wyoming bridge (kein API Key)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 10201;
        description = "Wyoming TTS port für Edge TTS.";
      };
      voice = lib.mkOption {
        type = lib.types.str;
        default = "de-DE-KatjaNeural";
        description = "Edge TTS Stimme (z. B. de-DE-KatjaNeural, de-DE-ConradNeural).";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      systemd.services.groq-stt-wyoming = {
        description = "Groq Whisper STT Wyoming bridge";
        after = [
          "network.target"
          "q958-secrets-provision.service"
        ];
        wants = [ "q958-secrets-provision.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = groqSttBridge;
          LoadCredentialEncrypted = [
            "groq_api_key:/var/lib/credstore.encrypted/groq_api_key.cred"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
        };
      };
      networking.firewall.allowedTCPPorts = [ cfg.port ];
    })

    (lib.mkIf (cfg.enable && cfg.tts.enable) {
      systemd.services.google-tts-wyoming = {
        description = "Google Cloud TTS Wyoming bridge";
        after = [
          "network.target"
          "q958-secrets-provision.service"
        ];
        wants = [ "q958-secrets-provision.service" ];
        wantedBy = [ "multi-user.target" ];
        # Startet erst wenn API Key versiegelt vorliegt (nach Credential-Setup)
        unitConfig.ConditionPathExists = "/var/lib/credstore.encrypted/google_tts_api_key.cred";
        serviceConfig = {
          Type = "simple";
          ExecStart = googleTtsBridge;
          LoadCredentialEncrypted = [
            "google_tts_api_key:/var/lib/credstore.encrypted/google_tts_api_key.cred"
          ];
          # "-" Prefix: kein Fehler wenn Env-Datei noch nicht existiert
          EnvironmentFile = [ "-/var/lib/secrets/google-tts.env" ];
          Restart = "on-failure";
          RestartSec = "5s";
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.edgeTts.enable) {
      systemd.services.edge-tts-wyoming = {
        description = "Microsoft Edge TTS Wyoming bridge";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = edgeTtsBridge;
          Restart = "on-failure";
          RestartSec = "5s";
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
        };
      };
      networking.firewall.allowedTCPPorts = [ cfg.edgeTts.port ];
    })
  ];
}
