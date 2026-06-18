# Security — Secrets im Git

## Was passiert ist

Das alte Repo (`grapefruit89/Nix-Grok`, Commit `d524580`) enthielt fälschlich:

- Notfall-`passwordHash` für User `nixos`
- `secrets.devKeys` mit Dev-Platzhaltern

**Altes Repo archivieren oder löschen** — die Historie ist kompromittiert. Kein `filter-repo` nötig: wir starten mit **frischem Git ohne Historie**.

## Neues Repo (ab init)

| Was | Wo |
|-----|-----|
| Secrets | `machines/q958/profile.local.nix` (**gitignored**) |
| Vorlage | `machines/q958/profile.local.nix.example` |
| Maschinen-Daten | `machines/q958/profile.nix` — **keine** Secrets |

```bash
cp machines/q958/profile.local.nix.example machines/q958/profile.local.nix
# Neue Werte eintragen (nach Rotation), niemals committen
```

## Rotation (Pflicht — alte Werte waren auf GitHub)

1. **Notfall-Passwort `nixos`** — neu setzen (`mkpasswd -m sha-512`)
2. **Alle Dev-Keys** neu generieren (nicht `q958-dev-*` wiederverwenden)
3. Pocket-ID: bei Encryption-Key-Wechsel ggf. DB reset
4. GitHub: altes Repo **private** oder **delete**; aktuelles Repo: **`grapefruit89/NixmitGROK`**

## .gitignore-Regeln

Alles Sensitive steht in `.gitignore` — u. a.:

- `profile.local.nix`, `secrets.sops.yaml`, `*.env`, `*.key`, `*.pem`
- `data/`, `*.db`, `*.sqlite` (Wissens-DBs lokal bauen)
- `.ssh/`, `.grok/`, `.cache/`

Vor Push prüfen:

```bash
git grep -E 'passwordHash\s*=\s*"\$|q958-dev-' -- ':!*.example' ':!docs/SECURITY.md' && echo FAIL || echo OK
```

## Dauerregeln

- Context7-Key nur `~/.config/context7/api_key`
- SOPS erst Stufe Production (Rollout 9+)
- SSH **Public** Keys in `users/*/profile.nix` sind OK — Private Keys nie