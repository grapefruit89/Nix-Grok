# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Voice Assistant — Groq Whisper STT Wyoming Bridge
#   services:
#     - groq-stt-wyoming
#   tags:
#     - iot
#     - home-automation
#     - voice
#     - stt
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

  groqSttBridge = pkgs.writeScript "groq-stt-bridge" ''
    #!${python}/bin/python3
    """Groq Whisper STT Wyoming bridge — antwortet auf Describe und transkribiert Audio."""
    import asyncio
    import io
    import json
    import os
    import sys
    import wave
    import urllib.request
    from pathlib import Path

    from wyoming.asr import Transcribe, Transcript
    from wyoming.audio import AudioChunk, AudioStart, AudioStop
    from wyoming.event import Event
    from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
    from wyoming.server import AsyncEventHandler, AsyncServer

    GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
    MODEL = "whisper-large-v3-turbo"
    LANGUAGE = "de"
    PORT = ${toString cfg.port}


    def _multipart(wav_bytes: bytes, api_key: str) -> bytes:
        """Groq API Multipart-Request senden, Transkript zurückgeben."""
        boundary = b"----WyomingGroqBridge"
        body = (
            b"--" + boundary + b"\r\n"
            b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
            b"Content-Type: audio/wav\r\n\r\n"
            + wav_bytes
            + b"\r\n--" + boundary + b"\r\n"
            b'Content-Disposition: form-data; name="model"\r\n\r\n'
            + MODEL.encode() + b"\r\n"
            b"--" + boundary + b"\r\n"
            b'Content-Disposition: form-data; name="language"\r\n\r\n'
            + LANGUAGE.encode() + b"\r\n"
            b"--" + boundary + b"\r\n"
            b'Content-Disposition: form-data; name="response_format"\r\n\r\njson\r\n'
            b"--" + boundary + b"--\r\n"
        )
        req = urllib.request.Request(
            GROQ_URL,
            data=body,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": f"multipart/form-data; boundary={boundary.decode()}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read()).get("text", "")


    class GroqSttHandler(AsyncEventHandler):
        def __init__(self, api_key: str, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._api_key = api_key
            self._chunks: list[AudioChunk] = []
            self._rate = 16000
            self._width = 2
            self._channels = 1

        async def handle_event(self, event: Event) -> bool:
            if Describe.is_type(event.type):
                await self.write_event(
                    Info(
                        asr=[
                            AsrProgram(
                                name="groq-whisper",
                                description="Groq Whisper Large v3 Turbo",
                                attribution=Attribution(
                                    name="Groq", url="https://groq.com"
                                ),
                                installed=True,
                                version="1.0.0",
                                models=[
                                    AsrModel(
                                        name="whisper-large-v3-turbo",
                                        description="Groq Whisper Large v3 Turbo (Deutsch)",
                                        attribution=Attribution(
                                            name="Groq", url="https://groq.com"
                                        ),
                                        installed=True,
                                        version="1.0.0",
                                        languages=["de", "en"],
                                    )
                                ],
                            )
                        ]
                    ).event()
                )
                return True

            if AudioStart.is_type(event.type):
                start = AudioStart.from_event(event)
                self._rate = start.rate
                self._width = start.width
                self._channels = start.channels
                self._chunks = []
                return True

            if AudioChunk.is_type(event.type):
                self._chunks.append(AudioChunk.from_event(event))
                return True

            if AudioStop.is_type(event.type):
                text = ""
                if self._chunks:
                    wav_io = io.BytesIO()
                    with wave.open(wav_io, "wb") as wf:
                        wf.setnchannels(self._channels)
                        wf.setsampwidth(self._width)
                        wf.setframerate(self._rate)
                        for chunk in self._chunks:
                            wf.writeframes(chunk.audio)
                    try:
                        text = await asyncio.get_event_loop().run_in_executor(
                            None, _multipart, wav_io.getvalue(), self._api_key
                        )
                    except Exception as exc:
                        print(f"Groq API error: {exc}", file=sys.stderr)
                await self.write_event(Transcript(text=text).event())
                return True

            return True


    async def main():
        creds = os.environ.get("CREDENTIALS_DIRECTORY")
        if not creds:
            print("CREDENTIALS_DIRECTORY not set", file=sys.stderr)
            sys.exit(1)
        key_file = Path(creds) / "groq_api_key"
        if not key_file.exists():
            print("groq_api_key missing in CREDENTIALS_DIRECTORY", file=sys.stderr)
            sys.exit(1)
        api_key = key_file.read_text().strip()

        server = AsyncServer.from_uri(f"tcp://0.0.0.0:{PORT}")
        print(f"Groq STT Wyoming bridge listening on port {PORT}", flush=True)
        await server.run(
            lambda *a, **kw: GroqSttHandler(api_key, *a, **kw)
        )


    asyncio.run(main())
  '';
in
{
  options.my.services.voice-assistant = {
    enable = lib.mkEnableOption "Groq STT Wyoming bridge";
    port = lib.mkOption {
      type = lib.types.port;
      default = 10300;
      description = "Wyoming STT port — HA entdeckt den Dienst automatisch.";
    };
  };

  config = lib.mkIf cfg.enable {
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

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ cfg.port ];
  };
}
