# Nix-Grok — Master Index

> **Einstiegspunkt für Menschen und KIs.**
> TOC.md ist das Navigations-Tool (Anker-Lookup). Dieses Dokument erklärt die Architektur.

---

## Was ist Nix-Grok?

Nix-Grok ist ein NixOS-Homelab-System für **q958** (Fujitsu ESPRIMO Q958) — deklarativ,
impermanence-ready, Unix-Socket-first, strikt No-Legacy.

**Technischer Stack:**
- OS: NixOS 25.11 (unstable) — Flake-basiert
- Ingress: Caddy mit UDS-Upstreams und SSO via Pocket-ID
- Auth: Pocket-ID (Passkey-first, kein Passwort)
- DNS: Technitium (DoT fail-closed)
- Netz: nftables, Netbird-VPN, skuid-Segmentierung
- Storage: ext4 persist + MergerFS (Tier B/C)
- Secrets: SOPS + age (ab Stufe 9)
- Monitoring: VictoriaMetrics + Loki + Grafana + Gatus

---

## Rollout-Modell (Stufen 1–9)

Das System wird in 9 Stufen aktiviert. Aktuell: **Stufe 8 (Development)**.

| Stufen | Was wird aktiviert |
|--------|-------------------|
| 1–3 | Boot, Kernel, Netzwerk, Storage-Pooling |
| 4–6 | Observability, VPN, Usenet-Stack |
| 7–8 | VictoriaMetrics, Crowdsec, Dropbear-Rescue, nftables-Härtung |
| 9 | Production: Impermanence (tmpfs /), SOPS-Secrets, Kernel-Hardening |

---

## Docs-Struktur

```
docs/
├── adr/              # Architecture Decision Records — WAS und WARUM (25 ADRs)
├── guides/           # Anleitungen — WIE (14 Guides + ANTIPATTERNS)
├── learnings/        # Retrospektiven & Befund-Registry — WAS WIR GELERNT HABEN
├── TOC.md            # KI-Navigations-Anker (auto-generiert, nicht manuell bearbeiten)
├── SOURCES.md        # Provenance: woher kommen unsere Ideen + Repo-Genealogie
├── ROADMAP.md        # Was kommt als nächstes
├── RUNBOOK.md        # Operativer Ablauf (Deploy, Restore, etc.)
├── SECURITY.md       # Security-Richtlinien
├── CHECKLISTS.md     # Pre-Rollout Checklisten
└── SPEC_REGISTRY.md  # Option-Spezifikationen (my.* Module)
```

---

## Kern-Entscheidungen (ADRs nach Thema)

### Netzwerk & DNS
- [ADR-001](adr/001-dns-dot-fail-closed.md) — DNS-over-TLS fail-closed (Technitium)
- [ADR-002](adr/002-ipv6-homelab-v4-only.md) — IPv4-only Homelab

### Storage
- [ADR-022](adr/022-no-raid-distance-parity.md) — Kein RAID, geografische Distanz

### Ingress & Caddy
- [ADR-019](adr/019-uds-first-philosophy.md) — Unix-Socket-First Philosophie

### Security
- [ADR-021](adr/021-sops-impermanence-boot-timing.md) — SOPS Boot-Timing mit Impermanence

### Architektur
- [ADR-020](adr/020-no-legacy-explicit-stack.md) — No-Legacy Explizit-Stack

---

## Wichtige Lib-Dateien (Architektur-Kern)

| Datei | Rolle |
|-------|-------|
| `lib/services-spec.nix` | **SSoT** für alle Services (socket:/port:, zone:, subdomain:) |
| `lib/caddy-ingress.nix` | Generiert Caddyfile aus services-spec |
| `lib/service-factory.nix` | `mkService` — systemd + Caddy + SSO in einem |
| `lib/forbidden-tech.nix` | Build-Zeit-Assertions (Docker, Cron, GUI, Formatter) |
| `lib/nftables-rules.nix` | Firewall-Regeln + skuid-Segmentierung |
| `lib/unix-sockets.nix` | Aktive UDS-Pfade (valkey, grafana, vaultwarden, postgresql) |

---

## Antipatterns (was wir explizit NICHT tun)

→ [docs/guides/ANTIPATTERNS.md](guides/ANTIPATTERNS.md)

Kurzliste: kein Docker, kein Cron, kein ZFS auf Consumer-HW, kein flake-parts, kein Lanzaboote,
kein SSH-Passwort, kein IFD, kein X11/Wayland, kein SSH socket-activated, kein RAID.

---

## Wo anfangen?

**Neues Service einrichten:** → [service-factory.nix](../lib/service-factory.nix) + [services-spec.nix](../lib/services-spec.nix)  
**Neue ADR schreiben:** → [docs/adr/TEMPLATE-ADR.md](adr/TEMPLATE-ADR.md)  
**Externen Befund dokumentieren:** → [docs/learnings/FINDINGS-REGISTRY.md](learnings/FINDINGS-REGISTRY.md)  
**System deployen:** → [RUNBOOK.md](RUNBOOK.md) + `scripts/nixos-rebuild-safe.sh`

---

*Letzte Aktualisierung: 2026-06-30*
