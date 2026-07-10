---
meta:
  role: doc
  purpose: Cloudflare DNS, ACME, DDNS und Token-Rotation auf q958
  status: current
  date: 2026-07-10
  docs:
    - docs/adr/7005-cloudflare-dns-acme-ddns.md
  tags:
    - cloudflare
    - dns
    - acme
    - ddns
---

# GUIDE: Cloudflare Integration {#guide-cloudflare}

## Überblick: Was CF für uns tut

```
Internet → Cloudflare DNS → q958 (93.226.213.104)
                ↓
         DDNS-Updater       → hält A-Records aktuell wenn IP wechselt
         ACME (lego)        → holt Wildcard-Cert via DNS-01-Challenge
         Caddy              → TLS-Terminierung mit ACME-Cert
```

CF ist **reines DNS** für uns — kein Proxy für Subdomains (grauer Wolke).
Ausnahme: Root-Domain `moritzbaumeister.de` ist proxied für DDoS-Schutz.

---

## Der CF-Token

**Typ:** `cfut_` — normaler Cloudflare User API Token  
**Wo hinterlegt:**
- `profile.local.nix` → `secrets.cloudflare.apiToken` (Laufzeit-Config)
- `~/.claude/settings.local.json` → MCP-Server-Konfiguration (für Claude-Sessions)

**Was er kann:** DNS lesen/schreiben auf moritzbaumeister.de und m7c5.de  
**Was er nicht kann:** Neue Tokens erstellen, eigene Permissions lesen

### Token rotieren

Im CF-Dashboard:
```
My Profile (Avatar oben rechts)
→ API Tokens
→ Token suchen → "..." → Edit → Roll Token
→ Neuen Wert kopieren
```

Dann in `profile.local.nix` eintragen:
```nix
secrets.cloudflare.apiToken = "cfut_NEUER_WERT";
```

Danach: `sudo nixos-rebuild switch --flake /etc/nixos#q958 --impure`

**Wichtig:** Den neuen Wert auch im Claude-MCP-Server aktualisieren (settings.local.json).

---

## DDNS-Updater

**Service:** `ddns-updater.service`  
**Was er tut:** Prüft alle N Minuten die öffentliche IP und aktualisiert CF-Records

Aktuell konfiguriert für `moritzbaumeister.de` (@ und *).  
m7c5.de zeigt absichtlich auf den Unraid-Server — DDNS nicht von q958 verwaltet.

```bash
# Status prüfen
sudo systemctl status ddns-updater

# Letzter Update-Log
journalctl -u ddns-updater -n 20 --no-pager
```

---

## ACME Wildcard-Zertifikat

**Service:** `acme-moritzbaumeister.de.service`  
**Timer:** `acme-renew-moritzbaumeister.de.timer`  
**Cert-Pfad:** `/var/lib/acme/moritzbaumeister.de/`

Das Zertifikat gilt für `*.moritzbaumeister.de` und wird automatisch erneuert.
Caddy liest es direkt aus `/var/lib/acme/`.

```bash
# Cert-Ablaufdatum prüfen
sudo openssl x509 -in /var/lib/acme/moritzbaumeister.de/cert.pem -noout -dates

# Manuell erneuern
sudo systemctl start acme-moritzbaumeister.de.service
```

---

## Neue Subdomains hinzufügen

**Kein CF-Schritt nötig.** Der Wildcard-Record `*.moritzbaumeister.de` fängt alles ab.

Nur in NixOS:
1. Service in `modules/` aktivieren
2. Caddy-Vhost in `lib/services-spec.nix` eintragen
3. `nixos-rebuild switch`

Fertig. Keine CF-Aktion, kein DNS-Eintrag, kein Cert-Request.

---

## DNS-Records manuell verwalten (via Claude MCP)

In einer Claude-Session mit CF-MCP:

```javascript
// A-Record erstellen
async () => cloudflare.request({
  method: 'POST',
  path: '/zones/facfa2e5e9ca3f00a93e145fe7684fd1/dns_records',
  body: { type: 'A', name: 'service.moritzbaumeister.de', content: '93.226.213.104', ttl: 1 }
})

// Record aktualisieren (Record-ID aus DNS-Liste)
async () => cloudflare.request({
  method: 'PATCH',
  path: '/zones/facfa2e5e9ca3f00a93e145fe7684fd1/dns_records/<ID>',
  body: { content: 'NEUE_IP' }
})
```

Zonen-IDs: moritzbaumeister.de = `facfa2e5e9ca3f00a93e145fe7684fd1`, m7c5.de = `d798de6c4cb9415fc7020b7d2eb24964`

---

## CF-Sicherheitseinstellungen (Free Tier)

Bereits optimal konfiguriert (verifiziert 2026-07-09):

| Einstellung | Wert | Änderbar via API? |
|---|---|---|
| SSL/TLS Mode | strict | ✅ |
| Security Level | high | ✅ |
| Always Use HTTPS | on | ✅ |
| Min TLS 1.2 | on | ✅ |
| TLS 1.3 | on | ✅ |
| HTTP/3 | on | ✅ |
| Brotli | on | ✅ |
| Bot Fight Mode | ? | ❌ Dashboard only |

**Bot Fight Mode** manuell aktivieren:  
CF Dashboard → Domain wählen → Security → Bots → Bot Fight Mode = On  
Für beide Domains (moritzbaumeister.de und m7c5.de) separat.

---

## Häufige Fehler

### cfk\_ Key funktioniert nicht für DNS

`cfk_...` ist der **Origin CA Key** — nur für CF-eigene SSL-Zertifikate,
nicht für DNS-API-Calls. Gibt Error 9103 oder 9109.  
Der richtige Token hat `cfut_`-Präfix.

### Token kann keine anderen Tokens erstellen

Unser `cfut_`-Token hat kein `token:edit`-Recht. Token-Erstellung nur:
- CF-Dashboard → My Profile → API Tokens → Create Token
- Oder mit dem Global API Key (37-stellige Hex-Zeichenkette)

### ACME schlägt fehl

```bash
journalctl -u acme-moritzbaumeister.de -n 50 --no-pager
```
Häufige Ursache: CF-Token abgelaufen → rotieren (siehe oben).