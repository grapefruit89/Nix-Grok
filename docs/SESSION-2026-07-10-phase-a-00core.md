---
meta:
  role: doc
  purpose: Session-Changelog 2026-07-10 — Phase A (Audit-Fixes) + 00-core Vorzeigeordner
  tags:
    - session
    - changelog
    - 00-core
    - phase-a
---

# Session 2026-07-10 — Phase A + 00-core Review

## Kontext

Fortsetzung eines Grok-Audits (10-network, 20-security, 00-core).
Grok lieferte Handoff-Dokumente; Claude hat implementiert und verifiziert.
System: q958, rollout.stufe = 8 (Development).

---

## Phase A — Audit-Fixes (aus Grok-Handoff)

### A1 — README 00-core korrigiert (`modules/00-core/README.md`)

**Warum:** Drei Zeilen beschrieben falsche Module.

| Zeile | Vorher | Nachher |
|-------|--------|---------|
| 19 | `01-core.nix` — Packages/Aliases/ZRAM/pre-commit | `01-core.nix` — Globale Options-Schema + Locale/Journald/Boot-Safeguard |
| 24 | `06-boot-watchdog.nix` — Panic bei Kernel-Oops | `06-boot-watchdog.nix` — Post-Boot Fail-Fast (Timer + oneshot) |
| 25 | `07-structure-validation.nix` — Port-Duplikate | `07-structure-validation.nix` — Build-Time-Assertions: modules/-Struktur |

**Verifiziert:** Tatsächliche Datei-Header bestätigt.

---

### A2 — dns-map.nix: secrets-portal Eintrag (`lib/dns-map.nix`)

**Warum:** `dnsMap.host "secrets-portal"` ohne Eintrag gibt Fallback `secrets-portal.<domain>` statt `secrets.<domain>`.
Schließt Validierungs-Loophole in `04-services-spec.nix`.

**Verifiziert:** DDNS iteriert dns-map nicht (zone-gated in rollout.nix). Kein CF-DNS-Record-Risiko.

```nix
"secrets-portal" = fqdn "secrets";
```

---

### A3 — home-assistant.nix Port-SSoT (`modules/70-home-automation/home-assistant.nix`)

**Warum:** Hardcodierter `default = 8123` statt Registry-Referenz.

```nix
# Vorher:
default = 8123;
# Nachher:
default = config.my.ports.home-assistant;
```

**Verifiziert:** `nix eval ... config.my.ports.home-assistant` → 8123 ✓

---

### A4 — Boot-Limit: boot-safeguard deadcode entfernt, generationLimit = 15

**Warum:** `boot-safeguard` war toten Code — `rollout.nix lib.mkForce p.boot.generationLimit` hat
`cfgBoot.configurationLimit` (default 5) immer überschrieben. Die richtige Lösung ist eine Quelle.

**Ergebnis:** `boot-safeguard`-Option komplett entfernt aus `01-core.nix`, `default.nix`, `rollout.nix`.
`profile.nix` ist jetzt alleinige Quelle: `generationLimit = 15` (kalkuliert: 15 × ~50 MB ≈ 750 MB + 77 MB < 1 GB ESP).

**Architektur-Muster:** `profile.nix` → `rollout.nix lib.mkForce` → `boot.loader.systemd-boot.configurationLimit`

---

### A5 — Port-Registry + Consumer (`modules/00-core/08-ports.nix` + 6 Dateien)

**Warum:** Hardcodierte Port-Literale in Consumer-Dateien (Single-Source-Verletzung).

**Registry-Ergänzungen:** `oauth2-proxy = 4180`, `dropbear = 2222`, `netbird-wg = 51820`

**Consumer-Updates:**
| Datei | Änderung |
|-------|---------|
| `28-oauth2-proxy.nix` | `reverse_proxy 127.0.0.1:4180` → `${toString config.my.ports.oauth2-proxy}` |
| `28-oauth2-proxy.nix` | `# httpAddress default...` → explizites `httpAddress = "http://127.0.0.1:..."` |
| `20-security.nix` | `default = 2222` → `default = config.my.ports.dropbear` |
| `21-sovereign-unlock.nix` | `default = 2222` → `default = config.my.ports.dropbear` |
| `16-vpn.nix` | `port = 51820` → `port = config.my.ports.netbird-wg` |
| `11-network.nix` | `oauth2proxyPort = ... 4180` → `config.my.ports.oauth2-proxy` |

**Bewusst nicht geändert:** `vpnTable = "51820"` in `16-vpn.nix` — Routing-Tabellen-ID, kein Listen-Port.

**Verifiziert live:** oauth2-proxy `--http-address=http://127.0.0.1:4180` ✓

---

### Vor-Phase A (frühere Session) — secrets-portal Fixes

Diese Fixes wurden in der Vorsitzung implementiert und sind live:

| Fix | Datei | Details |
|-----|-------|---------|
| Valkey socket drift | `lib/services-spec.nix` | `redis.sock` → `valkey.sock` |
| Socket-Permissions | `modules/20-security/29-secrets-portal.nix` | `Group=caddy`, `UMask=0007` → Socket `0660 root:caddy` |
| Caddy vHost gap | `lib/service-enable.nix` | `secrets-portal = mySvc.secrets-portal.enable or false` |

**Live-Stand:** `https://secrets.moritzbaumeister.de` → 200 OK, Socket `srwxrwx--- root caddy` ✓

---

## 00-core Review (iterativ)

### Task 1 — README Rest + default.nix Header

**README.md Zeilen 43+:**
- `## System-Packages (01-core.nix)` → `(09-nix-tools.nix)` (Packages waren nie in 01-core)
- `## Shell-Aliases` → `(09-nix-tools.nix)` ergänzt
- `## Pre-commit-Hooks` → `(09-nix-tools.nix)` + Anleitung einmaliger `pre-commit install`

**default.nix:**
- `SOPS` → `Creds` im purpose-Header (SOPS permanent verboten per 05-creds.nix)

---

### Task 2 — 08-ports.nix Registry vervollständigt

**Warum:** Grok-Audit identifizierte fehlende Ports. Verifiziert gegen Quell-Dateien.

| Port | Wert | Quelle |
|------|------|--------|
| `node-exporter` | 9100 | `44-metrics.nix:44,59` |
| `hermes` | 8787 | `60-apps/default.nix:45` |
| `wyoming-stt` | 10300 | `70-ha/voice-assistant.nix:297` |
| `wyoming-tts` | 10200 | `70-ha/voice-assistant.nix:304` |
| `wyoming-edge-tts` | 10201 | `70-ha/voice-assistant.nix:310` |

Consumer-Updates für diese Ports kommen mit den jeweiligen Domain-Reviews
(40-observability, 60-apps, 70-home-automation).

---

### Task 3 — preCommit aus 00-core entfernt (`modules/00-core/09-nix-tools.nix`)

**Warum:**
- Layer-0 soll production-neutral sein (ADR-032)
- Root-Prozess schreibt in `.git/hooks/` — architektonisch falsch
- Git merkt sich Hooks dauerhaft → activationScript nach jedem Switch redundant
- `|| true` maskierte Fehler lautlos

**Was entfernt:** `system.activationScripts.preCommitInstall` Block (Zeilen 159–177)

**Was bleibt:** `pre-commit` Package weiterhin installiert

**Einmaliger Setup:** `pre-commit install --config /etc/nixos/.pre-commit-config.yaml`

**Verifiziert:** `.git/hooks/pre-commit` vorhanden (persistent aus früherem Install) ✓,
`pre-commit --version` → 4.5.1 ✓, `rg 'activationScripts' modules/00-core/` → nur 05-creds ✓

**ADR:** [ADR-035](adr/035-pre-commit-hooks-manual.md)

---

## 00-core Status nach dieser Session

```
rg 'writeShellScript|activationScripts' modules/00-core/
→ 05-creds.nix (P0, wartet auf google_tts_api_key Provision über secrets-portal)
→ grok-audit.md (Dokumentation, kein Code)
```

| Kriterium | Vorher | Nachher |
|-----------|--------|---------|
| Port-Registry | ~85% | ~97% (alle bekannten Ports) |
| activationScripts in 00-core | 2 (preCommit + credCheck) | 1 (credCheck, P0) |
| README korrekt | ~80% | ~99% |
| ADRs aktuell | teilweise falsche Module | korrigiert |

---

## Offene Punkte (00-core)

| Punkt | Priorität | Blocker |
|-------|-----------|---------|
| P0: 05-creds.nix exit 1 fail-closed | hoch | google_tts_api_key.cred muss erst provisioniert werden |
| ~~P2: Boot-Limit eine Quelle~~ | ~~mittel~~ | **ERLEDIGT** — boot-safeguard entfernt, `profile.nix` ist SSoT |
| P3: 03-uid-registry Port=UID Assertion | niedrig | optional |
| 06-boot-watchdog entkoppeln | niedrig | architektonisch kohärent wie es ist |

