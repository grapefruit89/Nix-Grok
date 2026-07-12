# AGENTS — secrets/ (lokal, nicht im Git)

Dieses Verzeichnis ist für **lokale Credentials** — **nicht** für NixOS-Quellcode.

## Für KI-Agenten

| Erlaubt | Verboten |
|---------|----------|
| API-Keys, `.env`, lokale Tokens | `.nix`, `flake.nix`, Module, Skripte fürs Repo |
| Dateien, die **niemals** committet werden | Kopien von `/etc/nixos/**` |

NixOS-Konfiguration: nur **`/etc/nixos/`** (`profile.local.nix` ist gitignored, liegt aber **im Repo-Pfad** unter `machines/q958/`).

Secrets nach Setup: bevorzugt **secrets-portal** (`https://secrets.<domain>`) — siehe MOTD nach Login.