# Audit: modules/20-security
Datum: 2026-07-10
Auditor: Grok

## Bewertungskriterien (dieses Audit)

| Kriterium | Anforderung |
|-----------|-------------|
| **Timer ≠ Cron** | Kein `services.cron`; periodische Jobs nur `systemd.timers` + oneshot/service |
| **Kein POSIX-Legacy** | Kein `writeShellScript`, inline `script=`, `activationScripts`, `awk\|grep\|curl`-Pipelines wo Nix/systemd-native geht |
| **Deklarativ-first** | NixOS-Optionen, `environment.etc`, tmpfiles, Assertions — Runtime-Fetch nur wenn unvermeidbar |
| **SSoT / fail-closed** | Ports in Registry, Secrets über systemd-creds (Ziel), strukturierte Assertions |
| **Policy-Alignment** | `lib/forbidden-tech.nix`: kein cron, kein iptables, kein sops |

## Übersicht

`modules/20-security/` umfasst 10 Module: nftables-Firewall, SSH/Dropbear, LUKS Sovereign Unlock, Fail2ban/Auditd, ACME, Kernel-Policy/ Hardening, Production-Hardening, oauth2-proxy, secrets-portal.

**Gesamturteil:** Die **deklarativen Kernmodule** (nftables-Regeln via Lib, sysctl, ACME, hardened-core, kernel-policy, secrets-portal) sind stark. **Drei Dateien sind POSIX-lastig** und widersprechen deinem „kein Legacy"-Anspruch: `15-firewall.nix` (GeoIP-Shell), `20-security.nix` (Dropbear-Prep-Shell), `21-sovereign-unlock.nix` (initrd-Shell-Skripte). Fail2ban und oauth2-proxy nutzen noch `/var/lib/secrets/` statt systemd-creds.

**Cron:** Kein `services.cron` im Ordner ✓  
**Timer:** `nftables-geoip-update` nutzt `systemd.timers` ✓ (Implementierung aber Shell)

**Scope-Hinweis:** `my.security.crowdsec` und `my.security.runtime-guard` liegen in `40-observability/` — nicht in diesem Ordner, aber sicherheitsrelevant (dort ebenfalls Shell-Skripte).

---

## Legacy/POSIX-Inventar (Ordner gesamt)

| Datei | Cron | Timer | Shell/POSIX | Schwere |
|-------|------|-------|-------------|---------|
| default.nix | — | — | — | — |
| 15-firewall.nix | ✗ | ✓ timer | ✗ `writeShellScript` 35+ Zeilen | **Hoch** |
| 20-security.nix | ✗ | — | ✗ `writeShellScript` ExecStartPre | Mittel |
| 21-sovereign-unlock.nix | ✗ | — | ✗ 3× Shell (QR, initrd-shell) | Mittel* |
| 22-fail2ban.nix | ✗ | — | ~ Fail2ban selbst | Niedrig |
| 23-acme.nix | ✗ | — | — | — |
| 25-kernel-policy.nix | ✗ | — | — | — |
| 26-kernel-hardening.nix | ✗ | — | ~ `\|/bin/false` | Niedrig |
| 27-hardened-core.nix | ✗ | — | — | — |
| 28-oauth2-proxy.nix | ✗ | — | ~ `/var/lib/secrets/` | Mittel |
| 29-secrets-portal.nix | ✗ | — | — (Go-Binary) | — |

\* initrd-Shell teils unvermeidbar (kein Go im initrd), aber QR-Skript refactorbar

---

## Datei-Audits

### default.nix
**Zweck:** Import-Aggregator für alle Security-Submodule.

**Bewertung:** ⚠

**Findings:**
- Kein Meta-Header (im Gegensatz zu fast allen Untermodule).
- Import-Reihenfolge sinnvoll: Firewall (15) vor SSH (20), Kernel-Policy vor Hardening.

**Legacy/POSIX:** Keine.

**Empfehlung:** minor cleanup — Meta-Header ergänzen

---

### 15-firewall.nix
**Zweck:** nftables L4-Firewall (ersetzt `networking.firewall`), GeoIP-Whitelist, skuid-Segmentierung, strukturierte Assertions FIREWALL-001..003.

**Bewertung:** ⚠

**Findings:**
- **Deklarativ (gut):** Regelsatz komplett aus `lib/nftables-rules.nix` — keine Shell für Firewall-Logik. `checkRuleset = true`. Assertions mit `lib/assertions.nix`.
- **nftables statt iptables** — aligned mit `forbidden-tech.nix` POL-FT-005.
- **Timer statt Cron:** `systemd.timers.nftables-geoip-update` mit OnBootSec + 30d — korrekt.
- **✗ Legacy-Kern:** `nftables-geoip-update` ist ein 35-Zeilen-`writeShellScript`:
  - Runtime-Download von ipdeny.com via curl
  - grep/paste/wc Shell-Pipeline
  - `nft -f` mit generierter Datei
  - `|| true` bei grep und Country-Skip — Fehler werden verschluckt
  - Nicht reproduzierbar im Nix-Store — **imperativer Fetch bei jedem Timer-Lauf**
- **Deklarativer Upgrade-Pfad:** GeoIP-Zones als flake-input oder `nix-prefetch`-Derivation; nftables-Set via `networking.nftables.table` oder Generator in Nix; oneshot nur noch `nft load` aus Store-Pfad. Alternativ: kleines Go/Rust-Tool im `packages/`-Ordner (wie secrets-portal).
- `ipv6` Option default `true` — bei q958 wird via `network.nix` `my.security.firewall.ipv6 = false` gesetzt. Option-Default verwirrend für v4-only-Homelab.
- `geoipAutoUpdate` default `true` — aktiviert Shell-Service automatisch ab Stufe 8.

**Abhängigkeiten:** `lib/nftables-rules.nix`, `lib/assertions.nix`, `pkgs.curl`, `pkgs.nftables`

**Empfehlung:** refactor needed — GeoIP-Update von Shell auf Store-basiert oder Nix-Paket migrieren

---

### 20-security.nix
**Zweck:** SSH-Härtung (Dev vs. Production Zero-Trust), Dropbear Rescue-Daemon.

**Bewertung:** ⚠

**Findings:**
- **SSH Production:** Starke Krypto-Whitelist, Match-Block LAN/Tailscale vs. Rest, `PermitRootLogin no`, Key-only — vorbildlich.
- **Assertion:** Build bricht ohne Authorized Keys ab — fail-closed ✓
- **Dev-Mode:** Port 22 forced — rollout wechselt erst Stufe 9 auf productionSshPort.
- **Dropbear rescue:** `writeShellScript` ExecStartPre kopiert Keys mit mkdir/cp/chmod/chown — klassisches POSIX. **Upgrade:** tmpfiles-Regeln + `BindReadOnly` für authorized_keys, oder `StateDirectory` + Nix-generierte Key-Symlinks.
- **Dropbear-Port 2222** nicht in `my.ports` — Konventionsbruch.
- `banaction` iptables-Optionen existieren in fail2ban-Modul, nicht hier — ok.

**Legacy/POSIX:** `dropbear-rescue-prepare` Shell-Skript.

**Empfehlung:** minor cleanup — Dropbear-Prep deklarativ; Port in `my.ports.dropbear`

---

### 21-sovereign-unlock.nix
**Zweck:** LUKS Sovereign Unlock — TPM2, FIDO2, Clevis/Tang, initrd-SSH, QR-Fallback.

**Bewertung:** ⚠

**Findings:**
- **Deklarativ (gut):** `boot.initrd.luks`, clevis, initrd.systemd — NixOS-native.
- **initrd-SSH:** Shell als `boot.initrd.network.ssh.shell` — interaktive Notfall-Konsole, bash unvermeidbar im initrd-Kontext.
- **QR-Fallback:** `nms-qr-fallback` — 25-Zeilen Shell mit `awk`, `grep`, `sleep 30`, IP-Erkennung zur Laufzeit. **Upgrade:** statische IP aus `my.configs.server.lanIP` in Nix einbetten (kein awk); QR-Generierung als initrd-oneshot mit festem String.
- `sshPort` default 2222 — nicht in `my.ports`; Overlap mit Dropbear-Konzept.
- Nur aktiv wenn LUKS device gesetzt — q958 rollout: `erstAb 8` wenn LUKS vorhanden.

**Legacy/POSIX:** 2× `writeShellScript` (QR + initrd-shell). Initrd bash akzeptabel; QR-Skript refactorbar.

**Empfehlung:** minor cleanup — QR-Skript LAN-IP aus Config; Ports zentralisieren

---

### 22-fail2ban.nix
**Zweck:** Fail2ban Jails (SSH, Caddy JSON, Vaultwarden, Paperless, Recidive) + Auditd execve-Monitoring.

**Bewertung:** ⚠

**Findings:**
- **Deklarativ (gut):** Jails via `services.fail2ban` NixOS-Modul; Custom-Filter/Action als `environment.etc` — kein manuelles /etc editieren.
- **nftables-Integration:** `banaction = nftables-f2b-set` wenn Firewall aktiv — aligned mit Policy, kein iptables im Default.
- **Caddy-Jail:** `backend = "systemd"` + `journalmatch` — systemd-native Log-Quelle ✓
- **Legacy-Charakter:** Fail2ban selbst ist log-scraping-basiert (Python/Daemon) — kein reines systemd-/Nix-Muster, aber Standard für IPS. `banaction`-Enum enthält noch `iptables-multiport` als Option — Policy-Escape-Hatch.
- Auditd-Regeln deklarativ in `security.audit.rules` — gut.

**Legacy/POSIX:** Fail2ban-Daemon (upstream); keine eigenen Shell-Skripte in diesem Modul.

**Empfehlung:** keep as-is — optional: `iptables-*` aus banaction-Enum entfernen (Policy-Härte)

---

### 23-acme.nix
**Zweck:** Let's Encrypt DNS-01 Wildcard via Cloudflare (`security.acme`).

**Bewertung:** ✓

**Findings:**
- Vollständig deklarativ — `security.acme.certs` NixOS-Modul.
- `dnsResolver = 127.0.0.53:53` — durchdacht (Blocky auf LAN-IP, resolved auf Loopback).
- `environmentFile = /var/lib/secrets/cloudflare_acme_env` — **noch Legacy-Secrets-Pfad**, Migration zu systemd-creds laut ROADMAP offen.
- Kein Timer/Cron/Shell in diesem Modul — ACME-Renewal über systemd-Timer von NixOS acme-Service (upstream).

**Legacy/POSIX:** Secrets-Pfad `/var/lib/secrets/` (Migrationschuld, nicht Modul-Fehler).

**Empfehlung:** keep as-is — Secrets auf `LoadCredentialEncrypted` migrieren wenn Stufe 8+ creds aktiv

---

### 25-kernel-policy.nix
**Zweck:** Options-only für `my.core.kernel-slim` (Modus, Homelab-Profil). Implementierung in `machines/q958/kernel-slim.nix`.

**Bewertung:** ✓

**Findings:**
- Reine Options-Definition — maximale Deklarativität.
- Korrekte Auslagerung aus 00-core.

**Legacy/POSIX:** Keine.

**Empfehlung:** keep as-is

---

### 26-kernel-hardening.nix
**Zweck:** sysctl, boot.kernelParams, tmpfs-Hardening für /tmp, /dev/shm, /run/lock, Modul-Blacklist.

**Bewertung:** ✓

**Findings:**
- Fast vollständig deklarativ — sysctl-Attrset, fileSystems, kernelParams.
- `ip_unprivileged_port_start = 1001` — kollidiert konzeptuell mit `17-pocket-id.nix` (`mkDefault 1000`). Import-Reihe q958: 20-security vor 10-network → 1001 gewinnt; Pocket-ID Port 1001 passt knapp. Dokumentationslücke.
- `kernel.core_pattern = "|/bin/false"` — POSIX-Pipe-Trick, üblich für Core-Dump-Verbot.
- `vpnNeedsForward = false` hardcoded — korrekt für UID-Split-Tunnel statt IP-Forward.
- `disableIpv6Stack` default false — bewusst (::1 für Jellyfin), LAN-v6 via 10-network aus.

**Legacy/POSIX:** Nur `|/bin/false` (Kernel-API, akzeptabel).

**Empfehlung:** keep as-is — `ip_unprivileged_port_start` mit pocket-id-Modul abstimmen/dokumentieren

---

### 27-hardened-core.nix
**Zweck:** Production Stufe 9 — hideProcessInformation, lockKernelModules, Desktop-Dienste aus.

**Bewertung:** ✓

**Findings:**
- 100% deklarativ — `systemd.services.*.enable = false`, `security.hideProcessInformation`, kernel lockdown param.
- `pcscd` für FIDO2/LUKS — bewusst enabled.
- Kein Shell, kein Cron.

**Legacy/POSIX:** Keine.

**Empfehlung:** keep as-is

---

### 28-oauth2-proxy.nix
**Zweck:** OIDC Forward-Auth (Pocket-ID als IdP), Caddy vHost `oauth.${domain}`.

**Bewertung:** ⚠

**Findings:**
- **Deklarativ (gut):** `services.oauth2-proxy` NixOS-Modul, systemd-Abhängigkeit auf `q958-secrets-provision`.
- **Legacy-Secrets:** `keyFile` + `cookie.secretFile` unter `/var/lib/secrets/` — nicht systemd-creds; provisioning via Shell in `secrets.nix`.
- **Hardcodierter Port 4180** in Caddy-vHost und oauth2-default — nicht `my.ports`.
- **Ingress-Split:** Caddy-vHost hier statt `14-ingress.nix` — bewusst (oauth ist kein Spec-Eintrag), aber verteilte Ingress-SSoT.
- `ssl-insecure-skip-verify = true` — Dev-Workaround, Kommentar sagt entfernen nach ACME.

**Legacy/POSIX:** Secrets-Provisioning extern (POSIX in secrets.nix); Modul selbst ohne Shell.

**Empfehlung:** minor cleanup — Port in Registry; Secrets → systemd-creds; ssl-insecure entfernen nach ACME live

---

### 29-secrets-portal.nix
**Zweck:** Web-UI für systemd-creds Rotation (Go-Binary, Unix-Socket).

**Bewertung:** ✓

**Findings:**
- **Vorbildlich deklarativ:** Go-Paket `packages/secrets-portal`, Config als `pkgs.writeText` JSON, systemd-Service ohne Shell.
- UDS unter `/run/secrets-portal/` — aligned mit UDS-first.
- Phase 1 als root dokumentiert (systemd-creds host-key) — Phase 2 privilege-separation geplant.
- **Noch nicht aktiviert** auf q958 (`secrets-portal.enable` fehlt in rollout/default laut Handout).
- `restart_services` in Secret-Def — deklarative systemd-Integration für Rotation.

**Legacy/POSIX:** Keine.

**Empfehlung:** keep as-is — aktivieren + `my.creds.keys` befüllen (Handout-Punkt 1)

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| Cron-Verbot | ✓ | Kein cron in 20-security; Policy in 90-policy via forbidden-tech |
| systemd timers | ✓ | GeoIP-Update nutzt Timer |
| Shell-Legacy | ✗ | 3 Module mit writeShellScript (15, 20, 21) |
| nftables-only | ✓ | Firewall deklarativ; Fail2ban default nftables-f2b-set |
| Secrets-Migration | ⚠ | oauth2, acme noch `/var/lib/secrets/`; portal → systemd-creds ✓ |
| Security-Scope-Split | ⚠ | CrowdSec + runtime-guard in 40-observability (dort Shell) |
| Port-SSoT | ⚠ | 2222, 4180 nicht in `my.ports` |
| secrets-portal | ⚠ | Implementiert, nicht enabled |

## Priorisierte Empfehlungen (Legacy-Fokus)

1. **`15-firewall.nix` GeoIP-Update refactoren** — Store-basierte Prefixes oder `packages/geoip-update` Go-Binary; Shell eliminieren
2. **`20-security.nix` Dropbear-Prep** — tmpfiles + deklarative Key-Verdrahtung statt ExecStartPre-Shell
3. **`21-sovereign-unlock.nix` QR-Fallback** — LAN-IP aus `my.configs.server.lanIP`, kein awk zur Laufzeit
4. **Secrets-Migration** — oauth2-proxy + ACME von `/var/lib/secrets/` auf systemd-creds (28, 23)
5. **Ports zentralisieren** — dropbear 2222, oauth2 4180 in `08-ports.nix`
6. **secrets-portal aktivieren** — `my.services.secrets-portal.enable` in rollout
7. **iptables aus fail2ban-Enum** — Policy-Härte (22)
8. **CrowdSec/runtime-guard** — separates Audit in 40-observability (Shell dort ebenfalls)

## MCP-Verfügbarkeit

Für dieses Audit genutzt: **nixos** MCP (`nix info fail2ban`). Verfügbar zusätzlich: **grok_com_github**, **cloudflare**, **exa**. MCP ist aktiv und aufrufbar — bei Bedarf z. B. nixpkgs-Optionen live prüfen oder GitHub-Issues zu fail2ban/crowdsec nachschlagen.