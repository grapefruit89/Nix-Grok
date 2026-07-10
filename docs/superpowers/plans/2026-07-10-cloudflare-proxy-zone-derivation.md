# Cloudflare Proxy Zone Derivation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wildcard-DNS-Record bleibt unproxied; `external`-Zone-Services bekommen individuelle CF-Records mit `proxied: true`; Caddy erhält CF-IPv4-Ranges in `trusted_proxies` für korrekte IP-Extraktion.

**Architecture:** Zwei Datei-Änderungen in NixOS. `11-network.nix` erweitert `trusted_proxies` global um 15 CF-Ranges (nur `client_ip`-Auflösung betroffen, `remote_ip`/`private_admin` bleibt unberührt). `secrets.nix` generiert DDNS-Config mit 9 proxied External-Records zusätzlich zu den bestehenden 2 unproxied Records (Bare-Domain + Wildcard).

**Tech Stack:** NixOS, Caddy (Caddyfile global config), qdm12/ddns-updater, Cloudflare API v4, jq, Nix-String-Interpolation.

## Global Constraints

- `/etc/nixos` gehört root — Schreibzugriff nur via `sudo install -m 644 <src> <dst>`
- Commits mit: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`
- Nach jedem Commit: `sudo git -C /etc/nixos log --oneline -3` zur Verifikation
- CF-Token liegt in `/var/lib/secrets/cloudflare_api_token` (nicht in Git)
- `nixos-rebuild` via `sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch` (dry-build first)
- IPv6 ist auf q958 deaktiviert — nur IPv4-CF-Ranges nötig

---

## Precondition: CF Dashboard — SSL/TLS auf Full (strict) prüfen

**Manueller Browser-Schritt — vor dem nixos-rebuild erledigen.**

CF Dashboard → Deine Domain → SSL/TLS → Overview → Encryption mode muss auf **"Full (strict)"** stehen.

- [ ] CF Dashboard öffnen, SSL/TLS → Overview prüfen
- [ ] Falls nicht "Full (strict)": auf "Full (strict)" setzen, speichern

Wenn dieser Schritt übersprungen wird und der Modus auf "Flexible" steht: proxied Records erzeugen Redirect-Loops (HTTP→HTTPS→HTTP).

---

## Task 1: trusted_proxies um CF-IPv4-Ranges erweitern

**Files:**
- Modify: `modules/10-network/11-network.nix:124`

**Was und warum:** Caddy's globale `trusted_proxies`-Liste bestimmt, welchen Proxy-IPs Caddy beim Extrahieren der echten Client-IP via `CF-Connecting-IP`/`X-Forwarded-For` vertraut. Ohne CF-Ranges sieht Caddy für proxied Records immer die CF-Datacenter-IP statt der echten Nutzer-IP — CrowdSec und DSGVO-Log sind dann wertlos für External-Services.

**Sicherheitshinweis:** `trusted_proxies` beeinflusst ausschließlich `client_ip`-Matcher. `private_admin` nutzt `remote_ip` (direkte TCP-IP, Header-immun) — das ist von dieser Änderung nicht betroffen.

- [ ] **Schritt 1: Aktuelle Zeile in Scratchpad ansehen**

```bash
grep -n "trusted_proxies" /etc/nixos/modules/10-network/11-network.nix
```
Erwartete Ausgabe: `124:          trusted_proxies static private_ranges`

- [ ] **Schritt 2: Datei lesen (Pflicht vor Edit)**

`modules/10-network/11-network.nix` Zeilen 120–132 lesen.

- [ ] **Schritt 3: trusted_proxies-Zeile ersetzen**

Exakt diese Zeile ersetzen:
```
          trusted_proxies static private_ranges
```

Durch:
```
          trusted_proxies static private_ranges
            173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
            141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
            197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
            104.24.0.0/14   172.64.0.0/13   131.0.72.0/22
```

Die Ranges stammen von https://www.cloudflare.com/ips-v4 (verifiziert 2026-07-10).

- [ ] **Schritt 4: Nix-Eval prüfen (kein vollständiger Build)**

```bash
sudo nix eval --impure /etc/nixos#nixosConfigurations.q958.config.services.caddy.globalConfig 2>&1 | grep -A3 trusted_proxies
```
Erwartete Ausgabe: alle 15 CF-Ranges sichtbar in der evaluierten Config.

- [ ] **Schritt 5: Commit**

```bash
cd /etc/nixos
sudo git add modules/10-network/11-network.nix
sudo git commit -m "$(cat <<'EOF'
feat(caddy): trusted_proxies um CF-IPv4-Ranges erweitern

Caddy extrahiert für external-Zone echte Client-IPs via CF-Connecting-IP-Header.
CrowdSec und DSGVO-Log zeigen damit echte Nutzer-IPs statt CF-Datacenter-IPs.
remote_ip/private_admin unverändert (nur client_ip-Auflösung betroffen).

CF-Ranges von https://www.cloudflare.com/ips-v4 (2026-07-10).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
sudo git -C /etc/nixos log --oneline -3
```

---

## Task 2: DDNS-Config um External-Zone-Records erweitern

**Files:**
- Modify: `machines/q958/secrets.nix` (let-Block + jq-Block)

**Was und warum:** `q958-secrets-provision` generiert `/var/lib/ddns-updater/config.json`. Bisher: 2 Records (Bare-Domain + Wildcard, beide implizit unproxied). Neu: Wildcard + Bare-Domain bekommen explizit `proxied: false`. 9 External-Subdomains (`auth`, `seerr`, `files`, `links`, `ai`, `paperless`, `home`, `zigbee`, `amp`) bekommen `proxied: true`. ddns-updater pflegt dann alle 11 Records bei IP-Wechsel.

**Nix-Technik:** `externalSubdomains`-Liste wird im `let`-Block definiert. `externalJqEntries` verwendet `lib.concatStringsSep` um die 9 jq-Objekte zur Nix-Evaluierungszeit in den Shell-Script-String einzubauen. Das Ergebnis ist ein statisches Shell-Script — keine Runtime-Iteration nötig.

- [ ] **Schritt 1: Aktuelle let-Block-Zeilen lesen**

`machines/q958/secrets.nix` Zeilen 1–60 lesen. Bekannte relevante Zeilen:
- Zeile 49: `cfToken = (local.secrets.cloudflare or { }).apiToken or "";`
- Zeile 53: `ddnsFqdn = p.network.ddns.fqdn;`
- Zeile 54: `ddnsWildcardFqdn = p.network.ddns.wildcardFqdn;`

- [ ] **Schritt 2: Zwei Zeilen zum let-Block hinzufügen**

Nach Zeile 54 (`ddnsWildcardFqdn = ...`) einfügen:

```nix
  externalSubdomains = [ "auth" "seerr" "files" "links" "ai" "paperless" "home" "zigbee" "amp" ];
  externalJqEntries = lib.concatStringsSep ",\n          " (map (sub:
    ''{provider: "cloudflare", zone_identifier: $zone_id, domain: "${sub}.${ddnsFqdn}", proxied: true, ttl: 1, token: $token, ip_version: "ipv4"}''
  ) externalSubdomains);
```

- [ ] **Schritt 3: jq-Block lesen (Zeilen 192–202)**

`machines/q958/secrets.nix` Zeilen 190–210 lesen. Der aktuelle Block:

```bash
${pkgs.jq}/bin/jq -n \
  --arg token "${cfToken}" \
  --arg zone_id "$ZONE_ID" \
  --arg domain "${ddnsFqdn}" \
  --arg wildcard "${ddnsWildcardFqdn}" \
  '{
    settings: [
      {provider: "cloudflare", zone_identifier: $zone_id, domain: $domain,   ttl: 1, token: $token, ip_version: "ipv4"},
      {provider: "cloudflare", zone_identifier: $zone_id, domain: $wildcard, ttl: 1, token: $token, ip_version: "ipv4"}
    ]
  }' > ${secretsDir}/ddns-updater-config.json
```

- [ ] **Schritt 4: jq-Block ersetzen**

Den gesamten jq-Block (von `${pkgs.jq}/bin/jq` bis `ddns-updater-config.json`) ersetzen durch:

```bash
${pkgs.jq}/bin/jq -n \
  --arg token "${cfToken}" \
  --arg zone_id "$ZONE_ID" \
  --arg domain "${ddnsFqdn}" \
  --arg wildcard "${ddnsWildcardFqdn}" \
  '{
    settings: [
      {provider: "cloudflare", zone_identifier: $zone_id, domain: $domain,   proxied: false, ttl: 1, token: $token, ip_version: "ipv4"},
      {provider: "cloudflare", zone_identifier: $zone_id, domain: $wildcard, proxied: false, ttl: 1, token: $token, ip_version: "ipv4"},
      ${externalJqEntries}
    ]
  }' > ${secretsDir}/ddns-updater-config.json
```

Änderungen gegenüber vorher:
1. Beide bestehenden Records: `proxied: false` hinzugefügt (explizit, vorher implizit)
2. Nach Wildcard-Record: `,` + neue Zeile mit `${externalJqEntries}` (Nix-Interpolation)

- [ ] **Schritt 5: Nix-Eval des generierten Scripts prüfen**

```bash
sudo nix eval --impure --raw \
  /etc/nixos#nixosConfigurations.q958.config.systemd.services.q958-secrets-provision.serviceConfig.ExecStart \
  2>&1 | grep -A2 "proxied"
```
Erwartete Ausgabe: `proxied: false` für Wildcard/Bare-Domain, `proxied: true` für `auth`, `seerr` usw. sichtbar im generierten Script.

Alternativ das generierte Script direkt lesen:
```bash
sudo nix build --impure /etc/nixos#nixosConfigurations.q958.config.systemd.services.q958-secrets-provision.serviceConfig.ExecStart 2>/dev/null || true
# Pfad des Provision-Scripts:
sudo nix eval --impure --raw /etc/nixos#nixosConfigurations.q958.config.systemd.services.q958-secrets-provision.serviceConfig.ExecStart
# Script lesen:
cat $(sudo nix eval --impure --raw /etc/nixos#nixosConfigurations.q958.config.systemd.services.q958-secrets-provision.serviceConfig.ExecStart)
```
Erwartete Ausgabe: alle 11 Records in den `settings`-Array eingebettet, inkl. 9 `proxied: true`-Einträge.

- [ ] **Schritt 6: Commit**

```bash
cd /etc/nixos
sudo git add machines/q958/secrets.nix
sudo git commit -m "$(cat <<'EOF'
feat(ddns): external-Zone-Records in DDNS-Config (proxied: true)

9 External-Subdomains (auth, seerr, files, links, ai, paperless, home,
zigbee, amp) erhalten individuelle CF-Records mit proxied:true. Wildcard
und Bare-Domain bekommen explizit proxied:false. ddns-updater pflegt
alle 11 Records bei IP-Wechsel.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
sudo git -C /etc/nixos log --oneline -3
```

---

## Task 3: Ausrollen + End-to-End-Verifikation

**Files:** keine Änderungen

- [ ] **Schritt 1: Dry-Build**

```bash
sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-build
```
Erwartete Ausgabe: kein Fehler, `dry-build OK` oder ähnlich.

- [ ] **Schritt 2: Switch**

```bash
sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch
```

- [ ] **Schritt 3: Provision neu starten (schreibt neue DDNS-Config)**

```bash
sudo systemctl restart q958-secrets-provision
sudo journalctl -u q958-secrets-provision -n 30 --no-pager
```
Erwartete Ausgabe: kein `exit 1`, keine Fehler. DDNS-Config geschrieben.

- [ ] **Schritt 4: ddns-updater sofort-Update triggern**

```bash
sudo systemctl restart ddns-updater
sudo journalctl -u ddns-updater -n 30 --no-pager
```
Erwartete Ausgabe: Update für alle 11 Records (kein `error`).

- [ ] **Schritt 5: CF-DNS-Records per API verifizieren**

```bash
DOMAIN=$(sudo nix eval --raw --impure /etc/nixos#nixosConfigurations.q958.config.my.configs.identity.domain)
CFTOKEN=$(cat /var/lib/secrets/cloudflare_api_token)
ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CFTOKEN" | jq -r '.result[0].id')
curl -sf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&per_page=50" \
  -H "Authorization: Bearer $CFTOKEN" \
  | jq '.result[] | {name: .name, proxied: .proxied}' | sort
```

Erwartete Ausgabe:
```json
{ "name": "*.moritzbaumeister.de",          "proxied": false }
{ "name": "ai.moritzbaumeister.de",         "proxied": true  }
{ "name": "amp.moritzbaumeister.de",        "proxied": true  }
{ "name": "auth.moritzbaumeister.de",       "proxied": true  }
{ "name": "files.moritzbaumeister.de",      "proxied": true  }
{ "name": "home.moritzbaumeister.de",       "proxied": true  }
{ "name": "links.moritzbaumeister.de",      "proxied": true  }
{ "name": "moritzbaumeister.de",            "proxied": false }
{ "name": "paperless.moritzbaumeister.de",  "proxied": true  }
{ "name": "seerr.moritzbaumeister.de",      "proxied": true  }
{ "name": "zigbee.moritzbaumeister.de",     "proxied": true  }
```

- [ ] **Schritt 6: private_admin — LAN-Zugang zu internal-Service prüfen**

```bash
LANIP=$(sudo nix eval --raw --impure /etc/nixos#nixosConfigurations.q958.config.my.configs.server.lanIP)
# Von LAN aus (oder: curl gegen LAN-IP direkt):
curl -sv --resolve "grafana.$DOMAIN:443:$LANIP" "https://grafana.$DOMAIN" 2>&1 | grep "< HTTP"
```
Erwartete Ausgabe: `< HTTP/2 200` oder `< HTTP/2 302` (Grafana-Login). Kein 403.

- [ ] **Schritt 7: External-Service von außen erreichbar**

```bash
curl -sv "https://auth.$DOMAIN" 2>&1 | grep -E "< HTTP|Connected to"
```
Erwartete Ausgabe: `Connected to 104.xx.xx.xx` (CF-IP) + `< HTTP/2 200` oder `302` (Pocket-ID).

- [ ] **Schritt 8: Caddy-Logs zeigen echte IP für external-Service (nicht CF-IP)**

```bash
# Eine Anfrage gegen auth.$DOMAIN stellen, dann Log prüfen:
sudo journalctl -u caddy -n 20 --no-pager | grep "auth\." | jq '.request.remote_ip // .request.client_ip // .' 2>/dev/null || \
  sudo journalctl -u caddy -n 20 --no-pager | grep "auth\."
```
Erwartete Ausgabe: echte Internet-IP (z.B. `1.2.3.4`), keine CF-Datacenter-IP (`104.x.x.x`).
