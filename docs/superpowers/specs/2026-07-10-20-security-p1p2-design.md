---
meta:
  role: doc
  purpose: Design — 20-security P1/P2 Audit-Fixes (Dropbear, Sovereign Unlock, Fail2ban, oauth2-proxy)
  date: 2026-07-10
  tags:
    - security
    - audit
    - kiss
---

# Design: 20-security P1 + P2 Fixes

**Datum:** 2026-07-10
**Scope:** modules/20-security — vier chirurgische Fixes, kein Refactoring

---

## Fix 1 — Dropbear ExecStartPre entfernen (`20-security.nix`)

**Problem:** 14-zeiliger Shell-Block kopiert authorized_keys zur Laufzeit.

**Lösung:** `AuthorizedKeysFile` auf NixOS-managed Pfade zeigen lassen.
Dropbear liest direkt aus `/etc/ssh/authorized_keys.d/%u` (User) und
`/etc/ssh/authorized_keys.d/root` — kein Copy, kein mkdir, kein chmod.

**Entfernt:** gesamter `ExecStartPre`-Block.

---

## Fix 2 — Sovereign Unlock: Runtime-awk entfernen (`21-sovereign-unlock.nix`)

**Problem:** `IP=$(ip -4 addr show | grep ... | awk ... | cut ...)` — Runtime-Fetch.

**Lösung:** `config.my.configs.server.lanIP` zur Evaluationszeit interpolieren.
Die IP ist bereits in `profile.nix` definiert.

---

## Fix 3 — Fail2ban: iptables aus Enum entfernen (`2022-fail2ban.nix`)

**Problem:** `banaction`-Enum enthält `iptables-multiport` und `iptables-allports`,
obwohl `lib.mkForce "nftables-f2b-set"` diese bei aktivierter Firewall immer überschreibt.

**Lösung:** Enum auf `[ "nftables-f2b-set" ]` reduzieren — ehrliche Dokumentation.

---

## Fix 4 — oauth2-proxy: ssl-insecure-skip-verify entfernen (`2028-oauth2-proxy.nix`)

**Problem:** Dev-Workaround für nicht vorhandenes Let's Encrypt Cert.

**Bedingung erfüllt:** Wildcard-ACME-Cert (`*.moritzbaumeister.de`) ist aktiv.
Zeile kann entfernt werden.

---

## Nicht in Scope

- P0 GeoIP-Refactoring — eigenes Projekt
- Secrets-Migration ACME/oauth2 auf LoadCredentialEncrypted — secrets-portal SSL-Problem offen
- initrd-bash in 21-sovereign-unlock — dokumentierte Ausnahme, kein Fix nötig
