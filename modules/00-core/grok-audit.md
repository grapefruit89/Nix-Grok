# Audit: modules/00-core
Datum: 2026-07-11
Auditor: Grok (Drift-Prevention — Re-Audit nach Phase A)

## Übersicht

`modules/00-core/` ist die immer aktive Fundamentschicht. Zehn Nix-Module plus `default.nix` definieren `my.*`-Schema, Port-/Service-Registries, Guardrails, systemd-creds-Infrastruktur, Boot-Health und Dev-Tooling.

**Gesamturteil:** Architektur solide, SSoT-Prinzipien weitgehend umgesetzt. Phase-A-Fixes (README, Ports, Boot-Limit, 05-creds fail-closed) sind **erledigt**. Verbleibende Punkte sind bewusstes Scope-Design (boot-watchdog) und niedrige Priorität.

---

## Status vs. Audit 2026-07-10

| Finding (alt) | Status 2026-07-11 |
|---------------|-------------------|
| README veraltet | ✓ **Behoben** — `README.md` stimmt mit 01–09 + default.nix |
| Boot-Limit Doppelquelle | ✓ **Behoben** — `boot-safeguard` entfernt; SSoT: `profile.nix` → `rollout.nix` mkForce |
| HA-Port 8123 nicht in Registry | ✓ **Behoben** — `08-ports.nix` + `lib/services-spec.nix` |
| Fehlende Ports (oauth2, dropbear, netbird, …) | ✓ **Behoben** — alle in `08-ports.nix` |
| 05-creds activationScript + soft-check | ✓ **Behoben** — `credential-store-check` oneshot, `exit 1` fail-closed |
| 09-nix-tools activationScript pre-commit | ✓ **Behoben** — kein activationScript; manuelles `pre-commit install` |
| 06-boot-watchdog Scope-Creep | ⚠ **Offen (niedrig)** — Restart-Policies für Caddy/PostgreSQL noch hier |

---

## Datei-Audits (Kurz)

### default.nix — ✓
Import 01→09, kein rollout-Gating — korrekt.

### 01-core.nix — ✓
Globales Schema + Journald. `boot-safeguard` entfernt; `configurationLimit` nur via Maschinen-Rollout.

### 02-nixmeta-ban.nix — ✓
Build-Time NIXMETA-Verbot — unverändert gut.

### 03-uid-registry.nix — ✓
Dünner Wrapper um `lib/uid-registry.nix`.

### 04-services-spec.nix — ✓
Spec-Matrix + Port/DNS-Assertions. `home-assistant` nutzt `my.ports.home-assistant`.

### 05-creds.nix — ✓
systemd-creds Store + sops-Verbot. `credential-store-check` blockiert bei fehlenden `.cred`.
`my.creds.keys` auf q958: 10 Einträge (inkl. oauth2 + ACME ab 2026-07-11).

### 06-boot-watchdog.nix — ⚠
Post-Boot Health-Check sinnvoll; dienstspezifische Restart/Requires-Logik gehört langfristig in Domänenmodule.

### 07-structure-validation.nix — ✓
modules/-Struktur-Assertions.

### 08-ports.nix — ✓
Zentrale Registry: 40+ Ports inkl. HA, oauth2, dropbear, netbird, exportarr, wyoming, hermes, node-exporter.

### 09-nix-tools.nix — ✓
Nix-Tuning, CLI-Aliases, ZRAM. Kein activationScript.

### README.md — ✓
Aktuell (Stand 2026-07-10 Phase A).

---

## Querschnitts-Befunde

| Thema | Status | Detail |
|-------|--------|--------|
| Port-SSoT | ✓ | `08-ports.nix` vollständig für q958-Dienste |
| UID-SSoT | ✓ | Partielle Registry, Duplikat-Guard |
| Secrets | ✓ | systemd-creds aktiv ab Stufe 8 (`my.creds.enable`) |
| Boot-Limit | ✓ | `profile.nix` `generationLimit = 15` → `rollout.nix` |
| Cross-Layer | ⚠ | `06-boot-watchdog` → Linkwarden/Caddy/PostgreSQL |
| Dokumentation | ✓ | README synchron |

## Priorisierte Empfehlungen

1. **Boot-Watchdog entkoppeln** — Restart-Policies in 10-network/50-media (niedrig)
2. **Lücke Port 6004** — reservieren oder bewusst dokumentieren (kosmetisch)