# Security — Secrets im Git

## Was passiert ist

In den ersten Commits (`d524580`, `ffbb8bf`) lagen **fälschlich im Repo**:

- `machines/q958/profile.nix` → Notfall-`passwordHash` (nixos)
- `secrets.devKeys` → Dev-Platzhalter (Pocket-ID, Grafana, *arr API keys, …)

Das war **nicht guter Ton** — auch Dev-Secrets gehören nicht in öffentliche Git-Historie.

## Fix (ab Commit `security/remove-secrets`)

- Secrets nur in `machines/q958/profile.local.nix` (**gitignored**)
- Vorlage: `profile.local.nix.example`
- `profile.nix` im Repo enthält **keine** Secrets mehr

## Was du jetzt tun musst

1. **Notfall-Passwort `nixos` ändern** — Hash war auf GitHub sichtbar
2. **Alle `q958-dev-*` Keys rotieren** — Pocket-ID DB ggf. reset wenn Encryption-Key wechselt
3. GitHub: Settings → Secret scanning / ggf. Repo kurz private
4. Optional: Historie bereinigen mit `git filter-repo` (alte Commits enthalten noch Secrets)

```bash
# Nach Rotation auf q958:
cp machines/q958/profile.local.nix.example machines/q958/profile.local.nix
# Werte eintragen, niemals committen
```

## Regeln

- Nie `profile.local.nix`, `secrets.sops.yaml`, API-Keys committen
- Context7-Key nur `~/.config/context7/api_key`
- SOPS erst Stufe Production (Rollout 9+)