---
meta:
  role: doc
  purpose: Kaltstart q958 — curl one-liner, ohne Secrets, secrets-portal danach
  date: 2026-07-12
  status: current
  tags:
    - cold-start
    - bootstrap
    - secrets-portal
  docs:
    - scripts/cold-start-q958.sh
    - docs/EMERGENCY-RECOVERY.md
    - docs/guides/GUIDE-secrets-portal.md
---

# Guide: Kaltstart q958 (curl, ohne Secrets)

> CasaOS/Runtip-Stil: **ein curl-Befehl** vom Live-USB → gleiche NixOS-Config, Secrets später im Browser.

---

## Wann welches Skript?

| Situation | Skript | Befehl |
|-----------|--------|--------|
| **Neue Hardware / leere Platte** | `cold-start-q958.sh` | curl → install |
| **Unfall: Store noch da, bootet nicht** | `emergency-bootstrap-q958.sh` | curl → **recover** |
| **Unfall: recover scheitert** | `emergency-bootstrap-q958.sh` | curl → install (DATEN WEG) |

---

## Ein Befehl — neue Installation

NixOS Minimal ISO booten, dann:

```bash
curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/main/scripts/cold-start-q958.sh | sudo bash
```

Das Skript:

1. Klont das Repo (`main`)
2. Erstellt `profile.local.nix` aus `.example` (Platzhalter, **keine echten Secrets**)
3. `disko-q958.sh install` — GPT, NIXBOOT + NIXPERSIST
4. `nixos-install --flake /mnt/etc/nixos#q958 --impure`

---

## Secrets — was automatisch vs. was du liefern musst

### Automatisch (intern, beim Boot)

`media-secrets.nix` erzeugt bei `CHANGE_ME`:

- Prowlarr, Sonarr, Radarr, SABnzbd API-Keys
- Jellyseerr, Jellyfin-Admin-PW (falls leer)
- Gatus SSH-Keypair, oauth2-cookie-secret (teilweise)

### Du musst liefern (extern, secrets-portal)

Nach erstem Boot im LAN: `https://secrets.<domain>`

- Cloudflare API-Token (DDNS + ACME)
- Treasure Maps API-Key
- Usenet-Zugangsdaten
- PrivadoVPN WireGuard-Key
- Restic/Koofr (optional)
- oauth2/OIDC Client-Secrets (optional)

Portal-Doku: [`GUIDE-secrets-portal.md`](GUIDE-secrets-portal.md)

---

## Optional: eigene profile.local.nix vom USB

```bash
# USB unter /media/moritz/ mounten — Skript übernimmt automatisch:
/media/moritz/profile.local.nix
```

---

## Nach dem ersten Boot

```bash
# 1. Secrets im Portal setzen
# 2. Rebuild (Mensch):
sudo nixos-rebuild-safe.sh switch
```

---

## Siehe auch

- [EMERGENCY-RECOVERY.md](../EMERGENCY-RECOVERY.md) — Unfall 2026-07-12, recover
- [GUIDE-disko-learning.md](GUIDE-disko-learning.md) — disko Lernen, Stufen
- [GUIDE-secrets-portal.md](GUIDE-secrets-portal.md) — Secret-Rotation