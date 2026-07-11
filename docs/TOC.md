---
meta:
  role: toc
  generated: true
  purpose: Globales Inhaltsverzeichnis aller Heading-Anker aus docs/ für KI-Navigation
---

# Globales Inhaltsverzeichnis — /etc/nixos/docs

> **Automatisch generiert** — nicht manuell bearbeiten.
> Neu generieren: `sudo bash /etc/nixos/scripts/gen-toc.sh`
>
> **Für KIs:** Dieses Verzeichnis listet alle Anker aller Dokumente in docs/.
> Suche einen Abschnitt hier → navigiere direkt per Anker ohne jede Datei zu lesen.


## adr/1001-dns-dot-fail-closed.md

- [`#kontext`](adr/1001-dns-dot-fail-closed.md#kontext) — Kontext
- [`#entscheidung`](adr/1001-dns-dot-fail-closed.md#entscheidung) — Entscheidung
  - [`#technitium`](adr/1001-dns-dot-fail-closed.md#technitium) — Aktuelle Implementierung (ab 2026-06-28): Technitium
  - [`#limitation-blocky`](adr/1001-dns-dot-fail-closed.md#limitation-blocky) — Limitation vs. Original (Blocky)
- [`#diagnose`](adr/1001-dns-dot-fail-closed.md#diagnose) — Diagnose
- [`#fix`](adr/1001-dns-dot-fail-closed.md#fix) — Fix
- [`#konsequenzen`](adr/1001-dns-dot-fail-closed.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/1001-dns-dot-fail-closed.md#positiv) — Positiv
  - [`#negativ`](adr/1001-dns-dot-fail-closed.md#negativ) — Negativ / Trade-offs
  - [`#implementierung`](adr/1001-dns-dot-fail-closed.md#implementierung) — Implementierung
  - [`#verifikation`](adr/1001-dns-dot-fail-closed.md#verifikation) — Verifikation
- [`#alternativen`](adr/1001-dns-dot-fail-closed.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1001-dns-dot-fail-closed.md#siehe-auch) — Siehe auch

## adr/1002-ipv6-homelab-v4-only.md

- [`#kontext`](adr/1002-ipv6-homelab-v4-only.md#kontext) — Kontext
- [`#entscheidung`](adr/1002-ipv6-homelab-v4-only.md#entscheidung) — Entscheidung
- [`#konsequenzen`](adr/1002-ipv6-homelab-v4-only.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/1002-ipv6-homelab-v4-only.md#positiv) — Positiv
  - [`#negativ`](adr/1002-ipv6-homelab-v4-only.md#negativ) — Negativ / Trade-offs
  - [`#reaktivierung`](adr/1002-ipv6-homelab-v4-only.md#reaktivierung) — Wieder aktivieren (Checkliste)
  - [`#implementierung`](adr/1002-ipv6-homelab-v4-only.md#implementierung) — Implementierung
  - [`#verifikation`](adr/1002-ipv6-homelab-v4-only.md#verifikation) — Verifikation
- [`#alternativen`](adr/1002-ipv6-homelab-v4-only.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1002-ipv6-homelab-v4-only.md#siehe-auch) — Siehe auch

## adr/003-oom-cgroup-isolation.md

- [`#kontext`](adr/003-oom-cgroup-isolation.md#kontext) — Kontext
- [`#entscheidung`](adr/003-oom-cgroup-isolation.md#entscheidung) — Entscheidung
  - [`#tier-modell`](adr/003-oom-cgroup-isolation.md#tier-modell) — Tier-Modell
  - [`#implementierungsstand`](adr/003-oom-cgroup-isolation.md#implementierungsstand) — Implementierungsstand
- [`#diagnose`](adr/003-oom-cgroup-isolation.md#diagnose) — Diagnose
- [`#fix`](adr/003-oom-cgroup-isolation.md#fix) — Fix
- [`#konsequenzen`](adr/003-oom-cgroup-isolation.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/003-oom-cgroup-isolation.md#positiv) — Positiv
  - [`#negativ`](adr/003-oom-cgroup-isolation.md#negativ) — Negativ / Trade-offs
  - [`#implementierung`](adr/003-oom-cgroup-isolation.md#implementierung) — Implementierung
  - [`#verifikation`](adr/003-oom-cgroup-isolation.md#verifikation) — Verifikation
- [`#alternativen`](adr/003-oom-cgroup-isolation.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/003-oom-cgroup-isolation.md#siehe-auch) — Siehe auch

## adr/1004-unix-socket-upstreams.md

- [`#kontext`](adr/1004-unix-socket-upstreams.md#kontext) — Kontext
- [`#entscheidung`](adr/1004-unix-socket-upstreams.md#entscheidung) — Entscheidung
  - [`#tcp-ausnahmen`](adr/1004-unix-socket-upstreams.md#tcp-ausnahmen) — TCP-Ausnahmen
- [`#konsequenzen`](adr/1004-unix-socket-upstreams.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/1004-unix-socket-upstreams.md#positiv) — Positiv
  - [`#negativ`](adr/1004-unix-socket-upstreams.md#negativ) — Negativ
  - [`#implementierung`](adr/1004-unix-socket-upstreams.md#implementierung) — Implementierung
- [`#alternativen`](adr/1004-unix-socket-upstreams.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1004-unix-socket-upstreams.md#siehe-auch) — Siehe auch

## adr/005-critical-systemd-restart.md

- [`#kontext`](adr/005-critical-systemd-restart.md#kontext) — Kontext
- [`#entscheidung`](adr/005-critical-systemd-restart.md#entscheidung) — Entscheidung
- [`#diagnose`](adr/005-critical-systemd-restart.md#diagnose) — Diagnose
- [`#fix`](adr/005-critical-systemd-restart.md#fix) — Fix
- [`#konsequenzen`](adr/005-critical-systemd-restart.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/005-critical-systemd-restart.md#positiv) — Positiv
  - [`#negativ`](adr/005-critical-systemd-restart.md#negativ) — Negativ
  - [`#implementierung`](adr/005-critical-systemd-restart.md#implementierung) — Implementierung
- [`#alternativen`](adr/005-critical-systemd-restart.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/005-critical-systemd-restart.md#siehe-auch) — Siehe auch

## adr/2006-sops-migration-path.md

- [`#kontext`](adr/2006-sops-migration-path.md#kontext) — Kontext
- [`#entscheidung`](adr/2006-sops-migration-path.md#entscheidung) — Entscheidung
  - [`#migrationspfad`](adr/2006-sops-migration-path.md#migrationspfad) — Migrationspfad
- [`#konsequenzen`](adr/2006-sops-migration-path.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/2006-sops-migration-path.md#positiv) — Positiv
  - [`#negativ`](adr/2006-sops-migration-path.md#negativ) — Negativ
  - [`#implementierung`](adr/2006-sops-migration-path.md#implementierung) — Implementierung
- [`#alternativen`](adr/2006-sops-migration-path.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/2006-sops-migration-path.md#siehe-auch) — Siehe auch

## adr/007-dendritic-one-file-per-service.md

- [`#kontext`](adr/007-dendritic-one-file-per-service.md#kontext) — Kontext
- [`#entscheidung`](adr/007-dendritic-one-file-per-service.md#entscheidung) — Entscheidung
  - [`#konvention`](adr/007-dendritic-one-file-per-service.md#konvention) — Modulstruktur-Konvention
- [`#konsequenzen`](adr/007-dendritic-one-file-per-service.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/007-dendritic-one-file-per-service.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/007-dendritic-one-file-per-service.md#siehe-auch) — Siehe auch

## adr/2008-nftables-l4-hardening.md

- [`#kontext`](adr/2008-nftables-l4-hardening.md#kontext) — Kontext
- [`#entscheidung`](adr/2008-nftables-l4-hardening.md#entscheidung) — Entscheidung
  - [`#hohe-prioritaet`](adr/2008-nftables-l4-hardening.md#hohe-prioritaet) — Hohe Priorität (Stufe 8, implementiert)
  - [`#skuid-segmentierung`](adr/2008-nftables-l4-hardening.md#skuid-segmentierung) — Mittlere Priorität (Stufe 8+, skuid-Segmentierung)
  - [`#zurueckgestellt`](adr/2008-nftables-l4-hardening.md#zurueckgestellt) — Bewusst zurückgestellt
- [`#diagnose`](adr/2008-nftables-l4-hardening.md#diagnose) — Diagnose
- [`#fix`](adr/2008-nftables-l4-hardening.md#fix) — Fix
- [`#architektur`](adr/2008-nftables-l4-hardening.md#architektur) — Architektur
- [`#konsequenzen`](adr/2008-nftables-l4-hardening.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/2008-nftables-l4-hardening.md#alternativen) — Alternativen verworfen
- [`#changelog`](adr/2008-nftables-l4-hardening.md#changelog) — Changelog
- [`#siehe-auch`](adr/2008-nftables-l4-hardening.md#siehe-auch) — Siehe auch

## adr/2009-vpn-leak-check.md

- [`#kontext`](adr/2009-vpn-leak-check.md#kontext) — Kontext
- [`#entscheidung`](adr/2009-vpn-leak-check.md#entscheidung) — Entscheidung
- [`#diagnose`](adr/2009-vpn-leak-check.md#diagnose) — Diagnose
- [`#fix`](adr/2009-vpn-leak-check.md#fix) — Fix
- [`#konsequenzen`](adr/2009-vpn-leak-check.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/2009-vpn-leak-check.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/2009-vpn-leak-check.md#siehe-auch) — Siehe auch

## adr/010-production-ssh-impermanence.md

- [`#kontext`](adr/010-production-ssh-impermanence.md#kontext) — Kontext
- [`#entscheidung`](adr/010-production-ssh-impermanence.md#entscheidung) — Entscheidung
  - [`#stufenplan`](adr/010-production-ssh-impermanence.md#stufenplan) — Rollout-Stufenplan
- [`#konsequenzen`](adr/010-production-ssh-impermanence.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/010-production-ssh-impermanence.md#positiv) — Positiv
  - [`#negativ`](adr/010-production-ssh-impermanence.md#negativ) — Negativ
  - [`#implementierung`](adr/010-production-ssh-impermanence.md#implementierung) — Implementierung
- [`#alternativen`](adr/010-production-ssh-impermanence.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/010-production-ssh-impermanence.md#siehe-auch) — Siehe auch

## adr/011-unified-port-uid-schema.md

- [`#kontext`](adr/011-unified-port-uid-schema.md#kontext) — Kontext
- [`#entscheidung`](adr/011-unified-port-uid-schema.md#entscheidung) — Entscheidung
  - [`#ausnahmen`](adr/011-unified-port-uid-schema.md#ausnahmen) — Ausnahmen (unveränderlich)
  - [`#single-source`](adr/011-unified-port-uid-schema.md#single-source) — Single Source of Truth
- [`#konsequenzen`](adr/011-unified-port-uid-schema.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/011-unified-port-uid-schema.md#positiv) — Positiv
  - [`#negativ`](adr/011-unified-port-uid-schema.md#negativ) — Negativ
  - [`#unix-sockets`](adr/011-unified-port-uid-schema.md#unix-sockets) — Unix Socket Ausbau
- [`#implementierung`](adr/011-unified-port-uid-schema.md#implementierung) — Implementierung
- [`#migration`](adr/011-unified-port-uid-schema.md#migration) — Migration *arr UIDs
- [`#alternativen`](adr/011-unified-port-uid-schema.md#alternativen) — Alternativen verworfen
- [`#changelog`](adr/011-unified-port-uid-schema.md#changelog) — Changelog
- [`#siehe-auch`](adr/011-unified-port-uid-schema.md#siehe-auch) — Siehe auch

## adr/012-modern-cli-tools.md

- [`#kontext`](adr/012-modern-cli-tools.md#kontext) — Kontext
- [`#entscheidung`](adr/012-modern-cli-tools.md#entscheidung) — Entscheidung
  - [`#tools`](adr/012-modern-cli-tools.md#tools) — Installierte Tools
- [`#konsequenzen`](adr/012-modern-cli-tools.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/012-modern-cli-tools.md#positiv) — Positiv
  - [`#negativ`](adr/012-modern-cli-tools.md#negativ) — Negativ / Risiken
- [`#alternativen`](adr/012-modern-cli-tools.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/012-modern-cli-tools.md#siehe-auch) — Siehe auch

## adr/013-flake-portability.md

- [`#kontext`](adr/013-flake-portability.md#kontext) — Kontext
- [`#entscheidung`](adr/013-flake-portability.md#entscheidung) — Entscheidung
  - [`#experimental-features`](adr/013-flake-portability.md#experimental-features) — Welche experimental-features bleiben
  - [`#flakes-vs-channels`](adr/013-flake-portability.md#flakes-vs-channels) — Warum Flakes besser als Channels sind
  - [`#portabilitaet`](adr/013-flake-portability.md#portabilitaet) — Portabilitätsstrategie
  - [`#risiko`](adr/013-flake-portability.md#risiko) — Risikobewertung externe Abhängigkeiten
- [`#konsequenzen`](adr/013-flake-portability.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/013-flake-portability.md#positiv) — Positiv
  - [`#negativ`](adr/013-flake-portability.md#negativ) — Negativ
  - [`#implementierung`](adr/013-flake-portability.md#implementierung) — Implementierung
- [`#alternativen`](adr/013-flake-portability.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/013-flake-portability.md#siehe-auch) — Siehe auch

## adr/1014-caddy-security-headers-trusted-proxies.md

- [`#status`](adr/1014-caddy-security-headers-trusted-proxies.md#status) — Status
- [`#kontext`](adr/1014-caddy-security-headers-trusted-proxies.md#kontext) — Kontext
- [`#entscheidung`](adr/1014-caddy-security-headers-trusted-proxies.md#entscheidung) — Entscheidung
  - [`#snippets`](adr/1014-caddy-security-headers-trusted-proxies.md#snippets) — `lib/caddy-snippets.nix`
  - [`#network-config`](adr/1014-caddy-security-headers-trusted-proxies.md#network-config) — `modules/10-network/1090-host-network.nix`
- [`#konsequenzen`](adr/1014-caddy-security-headers-trusted-proxies.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/1014-caddy-security-headers-trusted-proxies.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1014-caddy-security-headers-trusted-proxies.md#siehe-auch) — Siehe auch

## adr/015-cpu-power-profiles-daemon-thermald.md

- [`#status`](adr/015-cpu-power-profiles-daemon-thermald.md#status) — Status
- [`#kontext`](adr/015-cpu-power-profiles-daemon-thermald.md#kontext) — Kontext
- [`#entscheidung`](adr/015-cpu-power-profiles-daemon-thermald.md#entscheidung) — Entscheidung
  - [`#ppd`](adr/015-cpu-power-profiles-daemon-thermald.md#ppd) — `services.power-profiles-daemon.enable = true`
  - [`#thermald`](adr/015-cpu-power-profiles-daemon-thermald.md#thermald) — `services.thermald.enable = true`
- [`#diagnose`](adr/015-cpu-power-profiles-daemon-thermald.md#diagnose) — Diagnose
- [`#fix`](adr/015-cpu-power-profiles-daemon-thermald.md#fix) — Fix
- [`#konsequenzen`](adr/015-cpu-power-profiles-daemon-thermald.md#konsequenzen) — Konsequenzen
- [`#verifikation`](adr/015-cpu-power-profiles-daemon-thermald.md#verifikation) — Verifikation
- [`#alternativen`](adr/015-cpu-power-profiles-daemon-thermald.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/015-cpu-power-profiles-daemon-thermald.md#siehe-auch) — Siehe auch

## adr/1016-caddy-security-headers-coop-scanners.md

- [`#status`](adr/1016-caddy-security-headers-coop-scanners.md#status) — Status
- [`#kontext`](adr/1016-caddy-security-headers-coop-scanners.md#kontext) — Kontext
  - [`#problem-server-header`](adr/1016-caddy-security-headers-coop-scanners.md#problem-server-header) — Problem 1: Server-Header gibt Caddy-Version preis
  - [`#problem-coop`](adr/1016-caddy-security-headers-coop-scanners.md#problem-coop) — Problem 2: Cross-Origin-Opener-Policy fehlte
  - [`#problem-scanner`](adr/1016-caddy-security-headers-coop-scanners.md#problem-scanner) — Problem 3: Keine Scanner-Blockierung
- [`#entscheidung`](adr/1016-caddy-security-headers-coop-scanners.md#entscheidung) — Entscheidung
  - [`#block-scanners-usage`](adr/1016-caddy-security-headers-coop-scanners.md#block-scanners-usage) — Verwendung von `block_scanners`
- [`#konsequenzen`](adr/1016-caddy-security-headers-coop-scanners.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/1016-caddy-security-headers-coop-scanners.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1016-caddy-security-headers-coop-scanners.md#siehe-auch) — Siehe auch

## adr/1017-caddy-health-checks-error-fallback.md

- [`#status`](adr/1017-caddy-health-checks-error-fallback.md#status) — Status
- [`#kontext`](adr/1017-caddy-health-checks-error-fallback.md#kontext) — Kontext
  - [`#problem-503`](adr/1017-caddy-health-checks-error-fallback.md#problem-503) — Problem 1: Keine 503-Fallback-Seite
  - [`#problem-health-checks`](adr/1017-caddy-health-checks-error-fallback.md#problem-health-checks) — Problem 2: Aktive Upstream-Health-Checks nicht praktikabel
- [`#entscheidung`](adr/1017-caddy-health-checks-error-fallback.md#entscheidung) — Entscheidung
  - [`#upstream-errors`](adr/1017-caddy-health-checks-error-fallback.md#upstream-errors) — Lösung: `(upstream_errors)` Snippet
  - [`#handle-errors-begruendung`](adr/1017-caddy-health-checks-error-fallback.md#handle-errors-begruendung) — Warum `handle_errors` statt `respond @unhealthy`
- [`#diagnose`](adr/1017-caddy-health-checks-error-fallback.md#diagnose) — Diagnose
- [`#fix`](adr/1017-caddy-health-checks-error-fallback.md#fix) — Fix
- [`#konsequenzen`](adr/1017-caddy-health-checks-error-fallback.md#konsequenzen) — Konsequenzen
- [`#verifikation`](adr/1017-caddy-health-checks-error-fallback.md#verifikation) — Verifikation
- [`#alternativen`](adr/1017-caddy-health-checks-error-fallback.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/1017-caddy-health-checks-error-fallback.md#siehe-auch) — Siehe auch

## adr/1018-caddy-dual-log-dsgvo.md

- [`#status`](adr/1018-caddy-dual-log-dsgvo.md#status) — Status
- [`#kontext`](adr/1018-caddy-dual-log-dsgvo.md#kontext) — Kontext
- [`#entscheidung`](adr/1018-caddy-dual-log-dsgvo.md#entscheidung) — Entscheidung
  - [`#architektur`](adr/1018-caddy-dual-log-dsgvo.md#architektur) — Architektur
  - [`#umsetzung`](adr/1018-caddy-dual-log-dsgvo.md#umsetzung) — Umsetzung
  - [`#dsgvo-felder`](adr/1018-caddy-dual-log-dsgvo.md#dsgvo-felder) — DSGVO-Felder maskiert
- [`#diagnose`](adr/1018-caddy-dual-log-dsgvo.md#diagnose) — Diagnose
- [`#fix`](adr/1018-caddy-dual-log-dsgvo.md#fix) — Fix
- [`#alternativen`](adr/1018-caddy-dual-log-dsgvo.md#alternativen) — Alternativen verworfen
- [`#konsequenzen`](adr/1018-caddy-dual-log-dsgvo.md#konsequenzen) — Konsequenzen
- [`#siehe-auch`](adr/1018-caddy-dual-log-dsgvo.md#siehe-auch) — Siehe auch

## adr/CLAUDE-GUIDE.md

- [`#quickstart`](adr/CLAUDE-GUIDE.md#quickstart) — Schnelleinstieg für KIs
- [`#markdown-features`](adr/CLAUDE-GUIDE.md#markdown-features) — Markdown-Funktionen die wir hier einsetzen
  - [`#heading-anchors`](adr/CLAUDE-GUIDE.md#heading-anchors) — 1. Heading-Anker
- [`#mein-abschnitt`](adr/CLAUDE-GUIDE.md#mein-abschnitt) — Mein Abschnitt
  - [`#frontmatter`](adr/CLAUDE-GUIDE.md#frontmatter) — 2. YAML-Frontmatter — maschinenlesbare Metadaten
  - [`#standard-sections`](adr/CLAUDE-GUIDE.md#standard-sections) — 3. Standardisierte ADR-Abschnitte
- [`#status`](adr/CLAUDE-GUIDE.md#status) — Status
- [`#kontext`](adr/CLAUDE-GUIDE.md#kontext) — Kontext
- [`#entscheidung`](adr/CLAUDE-GUIDE.md#entscheidung) — Entscheidung
- [`#diagnose`](adr/CLAUDE-GUIDE.md#diagnose) — Diagnose
- [`#fix`](adr/CLAUDE-GUIDE.md#fix) — Fix
- [`#konsequenzen`](adr/CLAUDE-GUIDE.md#konsequenzen) — Konsequenzen
- [`#alternativen`](adr/CLAUDE-GUIDE.md#alternativen) — Alternativen verworfen
- [`#siehe-auch`](adr/CLAUDE-GUIDE.md#siehe-auch) — Siehe auch
- [`#diagnose`](adr/CLAUDE-GUIDE.md#diagnose) — Diagnose
- [`#fix`](adr/CLAUDE-GUIDE.md#fix) — Fix
  - [`#cross-links`](adr/CLAUDE-GUIDE.md#cross-links) — 4. Cross-Links zwischen ADRs und Guides
- [`#siehe-auch`](adr/CLAUDE-GUIDE.md#siehe-auch) — Siehe auch
  - [`#mermaid`](adr/CLAUDE-GUIDE.md#mermaid) — 5. Mermaid-Diagramme
  - [`#collapsible`](adr/CLAUDE-GUIDE.md#collapsible) — 6. Collapsible Sections
  - [`#error-table`](adr/CLAUDE-GUIDE.md#error-table) — 7. Error-Tabelle im RUNBOOK
- [`#ki-workflow`](adr/CLAUDE-GUIDE.md#ki-workflow) — KI-Workflows
  - [`#ki-fehler-triage`](adr/CLAUDE-GUIDE.md#ki-fehler-triage) — Fehler-Triage
  - [`#ki-suche`](adr/CLAUDE-GUIDE.md#ki-suche) — Inhalt suchen ohne ganzen Ordner zu lesen
  - [`#ki-neue-adr`](adr/CLAUDE-GUIDE.md#ki-neue-adr) — Neue ADR anlegen
- [`#qualitaet`](adr/CLAUDE-GUIDE.md#qualitaet) — Qualitätscheckliste
- [`#verwandt`](adr/CLAUDE-GUIDE.md#verwandt) — Verwandte Dokumente

## adr/README.md

- [`#index`](adr/README.md#index) — Index
- [`#wann-neues-adr`](adr/README.md#wann-neues-adr) — Wann neues ADR?
- [`#dateiname`](adr/README.md#dateiname) — Dateiname
- [`#verknpfung-im-code`](adr/README.md#verknpfung-im-code) — Verknüpfung im Code
- [`#changelog`](adr/README.md#changelog) — Changelog

## adr/TEMPLATE-ADR.md

- [`#kontext`](adr/TEMPLATE-ADR.md#kontext) — Kontext
- [`#entscheidung`](adr/TEMPLATE-ADR.md#entscheidung) — Entscheidung
  - [`#teilentscheidung-a`](adr/TEMPLATE-ADR.md#teilentscheidung-a) — Teilentscheidung A
  - [`#teilentscheidung-b`](adr/TEMPLATE-ADR.md#teilentscheidung-b) — Teilentscheidung B
- [`#diagnose`](adr/TEMPLATE-ADR.md#diagnose) — Diagnose
- [`#fix`](adr/TEMPLATE-ADR.md#fix) — Fix
- [`#konsequenzen`](adr/TEMPLATE-ADR.md#konsequenzen) — Konsequenzen
  - [`#positiv`](adr/TEMPLATE-ADR.md#positiv) — Positiv
  - [`#negativ`](adr/TEMPLATE-ADR.md#negativ) — Negativ / Trade-offs
  - [`#implementierung`](adr/TEMPLATE-ADR.md#implementierung) — Implementierung
  - [`#verifikation`](adr/TEMPLATE-ADR.md#verifikation) — Verifikation
- [`#alternativen`](adr/TEMPLATE-ADR.md#alternativen) — Alternativen verworfen
- [`#changelog`](adr/TEMPLATE-ADR.md#changelog) — Changelog
- [`#siehe-auch`](adr/TEMPLATE-ADR.md#siehe-auch) — Siehe auch

## AUDIT-blocky-caddy-ipv6.md

- [`#1-executive-summary`](AUDIT-blocky-caddy-ipv6.md#1-executive-summary) — 1. Executive Summary
  - [`#was-dieses-dokument-abdeckt`](AUDIT-blocky-caddy-ipv6.md#was-dieses-dokument-abdeckt) — Was dieses Dokument abdeckt
- [`#2-blocky--dns-resolver`](AUDIT-blocky-caddy-ipv6.md#2-blocky--dns-resolver) — 2. Blocky — DNS-Resolver
  - [`#21-rolle`](AUDIT-blocky-caddy-ipv6.md#21-rolle) — 2.1 Rolle
  - [`#22-konfigurationsquellen-eine-wahrheit-pro-schicht`](AUDIT-blocky-caddy-ipv6.md#22-konfigurationsquellen-eine-wahrheit-pro-schicht) — 2.2 Konfigurationsquellen (eine Wahrheit pro Schicht)
  - [`#23-aktuelle-upstreams-dot-only`](AUDIT-blocky-caddy-ipv6.md#23-aktuelle-upstreams-dot-only) — 2.3 Aktuelle Upstreams (DoT only)
  - [`#24-blocky-settings-modul`](AUDIT-blocky-caddy-ipv6.md#24-blocky-settings-modul) — 2.4 Blocky-Settings (Modul)
  - [`#25-system-dns-kein-bypass`](AUDIT-blocky-caddy-ipv6.md#25-system-dns-kein-bypass) — 2.5 System-DNS (kein Bypass)
  - [`#26-assertions-build-bricht-bei-regression`](AUDIT-blocky-caddy-ipv6.md#26-assertions-build-bricht-bei-regression) — 2.6 Assertions (Build bricht bei Regression)
  - [`#27-systemd--crash-resilienz`](AUDIT-blocky-caddy-ipv6.md#27-systemd--crash-resilienz) — 2.7 systemd — Crash-Resilienz
  - [`#28-monitoring`](AUDIT-blocky-caddy-ipv6.md#28-monitoring) — 2.8 Monitoring
  - [`#29-abhngigkeiten`](AUDIT-blocky-caddy-ipv6.md#29-abhngigkeiten) — 2.9 Abhängigkeiten
  - [`#210-risiken--mitigation`](AUDIT-blocky-caddy-ipv6.md#210-risiken--mitigation) — 2.10 Risiken & Mitigation
- [`#3-caddy--reverse-proxy--ingress`](AUDIT-blocky-caddy-ipv6.md#3-caddy--reverse-proxy--ingress) — 3. Caddy — Reverse Proxy / Ingress
  - [`#31-rolle`](AUDIT-blocky-caddy-ipv6.md#31-rolle) — 3.1 Rolle
  - [`#32-konfigurationsquellen`](AUDIT-blocky-caddy-ipv6.md#32-konfigurationsquellen) — 3.2 Konfigurationsquellen
  - [`#33-start-reihenfolge-deadlock-vermeidung`](AUDIT-blocky-caddy-ipv6.md#33-start-reihenfolge-deadlock-vermeidung) — 3.3 Start-Reihenfolge (Deadlock-Vermeidung)
  - [`#34-systemd--crash-resilienz`](AUDIT-blocky-caddy-ipv6.md#34-systemd--crash-resilienz) — 3.4 systemd — Crash-Resilienz
  - [`#35-monitoring`](AUDIT-blocky-caddy-ipv6.md#35-monitoring) — 3.5 Monitoring
  - [`#36-abhngigkeiten-von-blocky`](AUDIT-blocky-caddy-ipv6.md#36-abhngigkeiten-von-blocky) — 3.6 Abhängigkeiten von Blocky
  - [`#37-crowdsec--fail2ban`](AUDIT-blocky-caddy-ipv6.md#37-crowdsec--fail2ban) — 3.7 CrowdSec / Fail2ban
- [`#4-blocky--caddy--zusammenspiel`](AUDIT-blocky-caddy-ipv6.md#4-blocky--caddy--zusammenspiel) — 4. Blocky ↔ Caddy — Zusammenspiel
- [`#5-ipv6-policy--homelab-ad-acta-v4-only`](AUDIT-blocky-caddy-ipv6.md#5-ipv6-policy--homelab-ad-acta-v4-only) — 5. IPv6-Policy — Homelab ad acta (v4-only)
  - [`#51-entscheidung`](AUDIT-blocky-caddy-ipv6.md#51-entscheidung) — 5.1 Entscheidung
  - [`#52-konfigurationsquelle`](AUDIT-blocky-caddy-ipv6.md#52-konfigurationsquelle) — 5.2 Konfigurationsquelle
  - [`#53-schichten-was-ipv6-wo-abschaltet`](AUDIT-blocky-caddy-ipv6.md#53-schichten-was-ipv6-wo-abschaltet) — 5.3 Schichten (was IPv6 wo abschaltet)
  - [`#54-was-nicht-abgeschaltet-ist`](AUDIT-blocky-caddy-ipv6.md#54-was-nicht-abgeschaltet-ist) — 5.4 Was NICHT abgeschaltet ist
  - [`#55-verifikation-runtime`](AUDIT-blocky-caddy-ipv6.md#55-verifikation-runtime) — 5.5 Verifikation (Runtime)
  - [`#56-ipv6-spter-wieder-aktivieren`](AUDIT-blocky-caddy-ipv6.md#56-ipv6-spter-wieder-aktivieren) — 5.6 IPv6 später wieder aktivieren
- [`#6-adrs-entscheidungslog-kurz`](AUDIT-blocky-caddy-ipv6.md#6-adrs-entscheidungslog-kurz) — 6. ADRs (Entscheidungslog kurz)
- [`#7-datei-index-ki-hier-anfangen`](AUDIT-blocky-caddy-ipv6.md#7-datei-index-ki-hier-anfangen) — 7. Datei-Index (KI: hier anfangen)
- [`#7-verifikations-checkliste-nach-jedem-rebuild`](AUDIT-blocky-caddy-ipv6.md#7-verifikations-checkliste-nach-jedem-rebuild) — 7. Verifikations-Checkliste (nach jedem Rebuild)
- [`#8-regeln-fr-ki-nderungen`](AUDIT-blocky-caddy-ipv6.md#8-regeln-fr-ki-nderungen) — 8. Regeln für KI-Änderungen
  - [`#niemals-ohne-explizite-user-freigabe`](AUDIT-blocky-caddy-ipv6.md#niemals-ohne-explizite-user-freigabe) — NIEMALS (ohne explizite User-Freigabe)
  - [`#immer-prfen-nach-dnsingress-nderungen`](AUDIT-blocky-caddy-ipv6.md#immer-prfen-nach-dnsingress-nderungen) — IMMER prüfen nach DNS/Ingress-Änderungen
- [`#10-entscheidungslog--wie-und-warum`](AUDIT-blocky-caddy-ipv6.md#10-entscheidungslog--wie-und-warum) — 10. Entscheidungslog — wie und warum
  - [`#101-dns-over-tls-dot-statt-klartext`](AUDIT-blocky-caddy-ipv6.md#101-dns-over-tls-dot-statt-klartext) — 10.1 DNS-over-TLS (DoT) statt Klartext
  - [`#102-127001-only--kein-1111-fallback`](AUDIT-blocky-caddy-ipv6.md#102-127001-only--kein-1111-fallback) — 10.2 `127.0.0.1` only — kein `1.1.1.1`-Fallback
  - [`#103-ipv6-homelab-ad-acta`](AUDIT-blocky-caddy-ipv6.md#103-ipv6-homelab-ad-acta) — 10.3 IPv6 Homelab „ad acta“
  - [`#104-unix-sockets-wo-sinnvoll`](AUDIT-blocky-caddy-ipv6.md#104-unix-sockets-wo-sinnvoll) — 10.4 Unix-Sockets (wo sinnvoll)
  - [`#105-libcritical-systemdnix`](AUDIT-blocky-caddy-ipv6.md#105-libcritical-systemdnix) — 10.5 `lib/critical-systemd.nix`
- [`#11-ram--oom--dienst-darf-das-os-nicht-mitreien`](AUDIT-blocky-caddy-ipv6.md#11-ram--oom--dienst-darf-das-os-nicht-mitreien) — 11. RAM & OOM — Dienst darf das OS nicht mitreißen
  - [`#111-problem`](AUDIT-blocky-caddy-ipv6.md#111-problem) — 11.1 Problem
  - [`#112-zwei-mechanismen-komplementr`](AUDIT-blocky-caddy-ipv6.md#112-zwei-mechanismen-komplementr) — 11.2 Zwei Mechanismen (komplementär)
  - [`#113-system-baseline-q958-32-gb`](AUDIT-blocky-caddy-ipv6.md#113-system-baseline-q958-32-gb) — 11.3 System-Baseline (q958, 32 GB)
  - [`#114-ist-stand-aller-rollout-dienste-stufe-8`](AUDIT-blocky-caddy-ipv6.md#114-ist-stand-aller-rollout-dienste-stufe-8) — 11.4 Ist-Stand aller Rollout-Dienste (Stufe 8)
    - [`#tier-0--betriebssystem-lebensader-nie-zuerst-killen`](AUDIT-blocky-caddy-ipv6.md#tier-0--betriebssystem-lebensader-nie-zuerst-killen) — Tier 0 — Betriebssystem-Lebensader (nie zuerst killen)
    - [`#tier-1--ingress--identitt-hoch-aber-begrenzbar`](AUDIT-blocky-caddy-ipv6.md#tier-1--ingress--identitt-hoch-aber-begrenzbar) — Tier 1 — Ingress & Identität (hoch, aber begrenzbar)
    - [`#tier-2--iot-bus-mittel`](AUDIT-blocky-caddy-ipv6.md#tier-2--iot-bus-mittel) — Tier 2 — IoT-Bus (mittel)
    - [`#tier-3--observability-wachsen-mit-logs`](AUDIT-blocky-caddy-ipv6.md#tier-3--observability-wachsen-mit-logs) — Tier 3 — Observability (wachsen mit Logs)
    - [`#tier-4--media--downloads-expendable-ram-spitzen`](AUDIT-blocky-caddy-ipv6.md#tier-4--media--downloads-expendable-ram-spitzen) — Tier 4 — Media & Downloads (expendable, RAM-Spitzen)
    - [`#tier-5--apps-expendable`](AUDIT-blocky-caddy-ipv6.md#tier-5--apps-expendable) — Tier 5 — Apps (expendable)
  - [`#115-empfohlene-ram-budgets-32-gb--richtwerte`](AUDIT-blocky-caddy-ipv6.md#115-empfohlene-ram-budgets-32-gb--richtwerte) — 11.5 Empfohlene RAM-Budgets (32 GB — Richtwerte)
  - [`#116-implementierungs-backlog-priorisiert`](AUDIT-blocky-caddy-ipv6.md#116-implementierungs-backlog-priorisiert) — 11.6 Implementierungs-Backlog (priorisiert)
  - [`#117-verifikation-nach-umsetzung`](AUDIT-blocky-caddy-ipv6.md#117-verifikation-nach-umsetzung) — 11.7 Verifikation nach Umsetzung
- [`#9-changelog`](AUDIT-blocky-caddy-ipv6.md#9-changelog) — 9. Changelog

## CHECKLISTS.md

- [`#neuer-dienst`](CHECKLISTS.md#neuer-dienst) — Neuen Dienst hinzufügen
  - [`#neuer-dienst-port-uid`](CHECKLISTS.md#neuer-dienst-port-uid) — Schritt 1 — Port und UID planen
  - [`#neuer-dienst-registry`](CHECKLISTS.md#neuer-dienst-registry) — Schritt 2 — UID-Registry und Port-Option
  - [`#neuer-dienst-modul`](CHECKLISTS.md#neuer-dienst-modul) — Schritt 3 — Modul-Datei anlegen
  - [`#neuer-dienst-rollout`](CHECKLISTS.md#neuer-dienst-rollout) — Schritt 4 — Rollout aktivieren
  - [`#neuer-dienst-secrets`](CHECKLISTS.md#neuer-dienst-secrets) — Schritt 5 — Secrets und Verzeichnisse
  - [`#neuer-dienst-dry-build`](CHECKLISTS.md#neuer-dienst-dry-build) — Schritt 6 — Dry-Build
  - [`#neuer-dienst-switch`](CHECKLISTS.md#neuer-dienst-switch) — Schritt 7 — Switch
  - [`#neuer-dienst-docs`](CHECKLISTS.md#neuer-dienst-docs) — Schritt 8 — Dokumentation
- [`#service-debuggen`](CHECKLISTS.md#service-debuggen) — Service debuggen
- [`#nixos-rebuild`](CHECKLISTS.md#nixos-rebuild) — nixos-rebuild Switch
- [`#neue-adr`](CHECKLISTS.md#neue-adr) — Neue ADR anlegen
- [`#siehe-auch`](CHECKLISTS.md#siehe-auch) — Siehe auch

## FILE-META.md

- [`#idee`](FILE-META.md#idee) — Idee
- [`#format-fr-nix--sh`](FILE-META.md#format-fr-nix--sh) — Format für `.nix` / `.sh`
- [`#format-fr-md`](FILE-META.md#format-fr-md) — Format für `.md`
- [`#layer-agentsmd`](FILE-META.md#layer-agentsmd) — Layer (AGENTS.md)
- [`#tridirektionale-verlinkung`](FILE-META.md#tridirektionale-verlinkung) — Tridirektionale Verlinkung
- [`#migration-vom-alten-purpose-block`](FILE-META.md#migration-vom-alten-purpose-block) — Migration vom alten PURPOSE-Block

## GUIDE-developer-experience.md

- [`#berblick`](GUIDE-developer-experience.md#berblick) — Überblick
- [`#tgliche-rebuilds-mit-nh`](GUIDE-developer-experience.md#tgliche-rebuilds-mit-nh) — Tägliche Rebuilds mit `nh`
- [`#datei-inspektion-mit-bat`](GUIDE-developer-experience.md#datei-inspektion-mit-bat) — Datei-Inspektion mit `bat`
- [`#verzeichnisse-mit-eza`](GUIDE-developer-experience.md#verzeichnisse-mit-eza) — Verzeichnisse mit `eza`
- [`#suchen-mit-fd-und-rg`](GUIDE-developer-experience.md#suchen-mit-fd-und-rg) — Suchen mit `fd` und `rg`
- [`#disk-bersicht-mit-dust-und-duf`](GUIDE-developer-experience.md#disk-bersicht-mit-dust-und-duf) — Disk-Übersicht mit `dust` und `duf`
- [`#system-monitoring-mit-btop`](GUIDE-developer-experience.md#system-monitoring-mit-btop) — System-Monitoring mit `btop`
- [`#nix-spezifische-tools`](GUIDE-developer-experience.md#nix-spezifische-tools) — Nix-spezifische Tools
- [`#shell-alias-bersicht`](GUIDE-developer-experience.md#shell-alias-bersicht) — Shell-Alias-Übersicht
- [`#fr-claude-code`](GUIDE-developer-experience.md#fr-claude-code) — Für Claude Code
- [`#referenzen`](GUIDE-developer-experience.md#referenzen) — Referenzen

## guides/ANTIPATTERNS.md

- [`#iptables`](guides/ANTIPATTERNS.md#iptables) — Legacy iptables-Firewall
- [`#media-flakes`](guides/ANTIPATTERNS.md#media-flakes) — Externe Media-Flakes (Nixarr/Nixflix als Input)
- [`#socat-uds`](guides/ANTIPATTERNS.md#socat-uds) — Socat-UDS-Bridges für Caddy
- [`#kopia`](guides/ANTIPATTERNS.md#kopia) — Kopia statt Restic
- [`#nixmeta`](guides/ANTIPATTERNS.md#nixmeta) — Thymis / NIXMETA-Auto-Import
- [`#ssh-rescue`](guides/ANTIPATTERNS.md#ssh-rescue) — SSH-Rescue auf Production-Port
- [`#tmpfs-logs`](guides/ANTIPATTERNS.md#tmpfs-logs) — Logs auf tmpfs ohne Journal-Persist
- [`#bastelmodus`](guides/ANTIPATTERNS.md#bastelmodus) — Bastelmodus (imperative Overrides)
- [`#jellyfin-bypass`](guides/ANTIPATTERNS.md#jellyfin-bypass) — User-Agent Jellyfin-Bypass
- [`#siehe-auch`](guides/ANTIPATTERNS.md#siehe-auch) — Siehe auch

## guides/GUIDE-data-management.md

- [`#rsync`](guides/GUIDE-data-management.md#rsync) — rsync
- [`#rclone`](guides/GUIDE-data-management.md#rclone) — rclone
- [`#restic`](guides/GUIDE-data-management.md#restic) — restic
- [`#ssot`](guides/GUIDE-data-management.md#ssot) — SSoT
- [`#siehe-auch`](guides/GUIDE-data-management.md#siehe-auch) — Siehe auch

## guides/GUIDE-dendritic-architecture.md

- [`#regeln`](guides/GUIDE-dendritic-architecture.md#regeln) — Regeln (q958)
- [`#media-stack`](guides/GUIDE-dendritic-architecture.md#media-stack) — Media-Stack (50-media)
- [`#neuer-dienst`](guides/GUIDE-dendritic-architecture.md#neuer-dienst) — Neuer Dienst — Checkliste
- [`#was-wir-nicht-machen`](guides/GUIDE-dendritic-architecture.md#was-wir-nicht-machen) — Was wir nicht machen
- [`#siehe-auch`](guides/GUIDE-dendritic-architecture.md#siehe-auch) — Siehe auch

## guides/GUIDE-disk-health.md

- [`#dienste`](guides/GUIDE-disk-health.md#dienste) — Dienste
- [`#ui`](guides/GUIDE-disk-health.md#ui) — UI
- [`#gatus-checks`](guides/GUIDE-disk-health.md#gatus-checks) — Checks (Gatus)
- [`#betrieb`](guides/GUIDE-disk-health.md#betrieb) — Betrieb
- [`#siehe-auch`](guides/GUIDE-disk-health.md#siehe-auch) — Siehe auch

## guides/GUIDE-flake-portability.md

- [`#warum`](guides/GUIDE-flake-portability.md#warum) — Warum das System in 2 Jahren noch funktioniert
- [`#szenario-a`](guides/GUIDE-flake-portability.md#szenario-a) — Szenario A: Neuer Rechner mit Internet
- [`#szenario-b`](guides/GUIDE-flake-portability.md#szenario-b) — Szenario B: Neuer Rechner, KEIN Internet (Tier-2-Archiv)
- [`#szenario-c`](guides/GUIDE-flake-portability.md#szenario-c) — Szenario C: Komplettes System-Snapshot (Tier 3)
- [`#nixpkgs-commits`](guides/GUIDE-flake-portability.md#nixpkgs-commits) — Was nixpkgs-Commits über GitHub angeht
- [`#reale-risiken`](guides/GUIDE-flake-portability.md#reale-risiken) — Was IST ein reales Risiko
- [`#jahresroutine`](guides/GUIDE-flake-portability.md#jahresroutine) — Checkliste: Jahresroutine (5 Minuten)
- [`#experimental-features`](guides/GUIDE-flake-portability.md#experimental-features) — Experimental-Features: Was bleibt, was nicht
- [`#siehe-auch`](guides/GUIDE-flake-portability.md#siehe-auch) — Siehe auch

## guides/GUIDE-media-stack.md

- [`#dateien`](guides/GUIDE-media-stack.md#dateien) — Dendritische Dateien
- [`#vpn-netns`](guides/GUIDE-media-stack.md#vpn-netns) — VPN-NetNS
- [`#jellyfin`](guides/GUIDE-media-stack.md#jellyfin) — Jellyfin
- [`#arr`](guides/GUIDE-media-stack.md#arr) — *arr (Sonarr/Radarr/Readarr/Prowlarr)
- [`#mediacover`](guides/GUIDE-media-stack.md#mediacover) — MediaCover (Tier B)
- [`#config-sync`](guides/GUIDE-media-stack.md#config-sync) — Config-Sync
- [`#qualitaetsprofile`](guides/GUIDE-media-stack.md#qualitaetsprofile) — Qualitätsprofile
- [`#siehe-auch`](guides/GUIDE-media-stack.md#siehe-auch) — Siehe auch

## guides/GUIDE-network-database.md

- [`#architektur`](guides/GUIDE-network-database.md#architektur) — Architektur
- [`#postgresql`](guides/GUIDE-network-database.md#postgresql) — PostgreSQL
- [`#valkey`](guides/GUIDE-network-database.md#valkey) — Valkey
- [`#blocky`](guides/GUIDE-network-database.md#blocky) — Blocky
- [`#siehe-auch`](guides/GUIDE-network-database.md#siehe-auch) — Siehe auch

## guides/GUIDE-nftables-hardening.md

- [`#rollen-trennung`](guides/GUIDE-nftables-hardening.md#rollen-trennung) — Rollen-Trennung
- [`#chain-ablauf`](guides/GUIDE-nftables-hardening.md#chain-ablauf) — Chain-Ablauf
- [`#optionen`](guides/GUIDE-nftables-hardening.md#optionen) — Optionen (`my.security.firewall`)
- [`#fail2ban`](guides/GUIDE-nftables-hardening.md#fail2ban) — Fail2ban ↔ nftables
- [`#skuid`](guides/GUIDE-nftables-hardening.md#skuid) — skuid (UID-Registry)
- [`#verifikation`](guides/GUIDE-nftables-hardening.md#verifikation) — Verifikation nach Rebuild
- [`#alerting`](guides/GUIDE-nftables-hardening.md#alerting) — Alerting (optional)
- [`#siehe-auch`](guides/GUIDE-nftables-hardening.md#siehe-auch) — Siehe auch

## guides/GUIDE-observability-kurz.md

- [`#morgens`](guides/GUIDE-observability-kurz.md#morgens) — Morgens (2 Minuten)
- [`#roter-check`](guides/GUIDE-observability-kurz.md#roter-check) — Bei rotem Gatus-Check
- [`#logs`](guides/GUIDE-observability-kurz.md#logs) — Logs (VLG)
- [`#alerts`](guides/GUIDE-observability-kurz.md#alerts) — Alerts (Stufe 8+)
- [`#nicht-genutzt`](guides/GUIDE-observability-kurz.md#nicht-genutzt) — Was wir nicht nutzen
- [`#schnellbefehle`](guides/GUIDE-observability-kurz.md#schnellbefehle) — Schnellbefehle
- [`#siehe-auch`](guides/GUIDE-observability-kurz.md#siehe-auch) — Siehe auch

## guides/GUIDE-observability.md

- [`#gatus`](guides/GUIDE-observability.md#gatus) — Gatus
- [`#unix-socket-checks`](guides/GUIDE-observability.md#unix-socket-checks) — Unix-Socket-Checks
- [`#vlg`](guides/GUIDE-observability.md#vlg) — VLG (Vector / Loki / Grafana)
- [`#crowdsec`](guides/GUIDE-observability.md#crowdsec) — CrowdSec
- [`#alerting`](guides/GUIDE-observability.md#alerting) — Alerting (`05-alerting.nix`)
- [`#rollout`](guides/GUIDE-observability.md#rollout) — Rollout
- [`#siehe-auch`](guides/GUIDE-observability.md#siehe-auch) — Siehe auch

## guides/GUIDE-security-secrets.md

- [`#modi`](guides/GUIDE-security-secrets.md#modi) — Modi
- [`#ssh-haertung`](guides/GUIDE-security-secrets.md#ssh-haertung) — SSH-Härtung (Production)
- [`#sovereign-unlock`](guides/GUIDE-security-secrets.md#sovereign-unlock) — Sovereign Unlock
- [`#secrets`](guides/GUIDE-security-secrets.md#secrets) — Secrets (aktuell)
- [`#hardened-core`](guides/GUIDE-security-secrets.md#hardened-core) — Hardened Core (Stufe 9 / Production)
- [`#kernel-haertung`](guides/GUIDE-security-secrets.md#kernel-haertung) — Kernel-Härtung (Stufe 8+)
- [`#fail2ban`](guides/GUIDE-security-secrets.md#fail2ban) — Fail2ban
- [`#notfall`](guides/GUIDE-security-secrets.md#notfall) — Notfall
- [`#siehe-auch`](guides/GUIDE-security-secrets.md#siehe-auch) — Siehe auch

## guides/GUIDE-server-map.md

- [`#10-network`](guides/GUIDE-server-map.md#10-network) — 10-network
- [`#40-observability`](guides/GUIDE-server-map.md#40-observability) — 40-observability
- [`#50-media`](guides/GUIDE-server-map.md#50-media) — 50-media
- [`#60-apps`](guides/GUIDE-server-map.md#60-apps) — 60-apps
- [`#70-forge`](guides/GUIDE-server-map.md#70-forge) — 70-forge
- [`#infrastruktur`](guides/GUIDE-server-map.md#infrastruktur) — Infrastruktur (kein Caddy)
- [`#neue-services`](guides/GUIDE-server-map.md#neue-services) — Neue Services einbinden
- [`#debugging`](guides/GUIDE-server-map.md#debugging) — Debugging
- [`#siehe-auch`](guides/GUIDE-server-map.md#siehe-auch) — Siehe auch

## guides/GUIDE-storage-tiers.md

- [`#tier-policy`](guides/GUIDE-storage-tiers.md#tier-policy) — Tier-Policy (q958)
- [`#impermanence`](guides/GUIDE-storage-tiers.md#impermanence) — Impermanence (Stufe 9)
- [`#mediacover`](guides/GUIDE-storage-tiers.md#mediacover) — MediaCover / Cache (Tier B)
- [`#pending-disks`](guides/GUIDE-storage-tiers.md#pending-disks) — Pending Disks Watcher
- [`#restic`](guides/GUIDE-storage-tiers.md#restic) — Restic
- [`#storage-mover`](guides/GUIDE-storage-tiers.md#storage-mover) — Storage Mover
- [`#deferred-deletion`](guides/GUIDE-storage-tiers.md#deferred-deletion) — Deferred Deletion (HDD-sparend)
- [`#siehe-auch`](guides/GUIDE-storage-tiers.md#siehe-auch) — Siehe auch

## guides/TEMPLATE-GUIDE.md

- [`#ueberblick`](guides/TEMPLATE-GUIDE.md#ueberblick) — Überblick
- [`#abschnitt-eins`](guides/TEMPLATE-GUIDE.md#abschnitt-eins) — Abschnitt Eins
  - [`#abschnitt-eins-details`](guides/TEMPLATE-GUIDE.md#abschnitt-eins-details) — Unterabschnitt
- [`#abschnitt-zwei`](guides/TEMPLATE-GUIDE.md#abschnitt-zwei) — Abschnitt Zwei
- [`#verifikation`](guides/TEMPLATE-GUIDE.md#verifikation) — Verifikation
- [`#probleme`](guides/TEMPLATE-GUIDE.md#probleme) — Häufige Probleme
- [`#siehe-auch`](guides/TEMPLATE-GUIDE.md#siehe-auch) — Siehe auch

## memory_oom.md

- [`#1-ziel`](memory_oom.md#1-ziel) — 1. Ziel
- [`#2-tier-modell`](memory_oom.md#2-tier-modell) — 2. Tier-Modell
- [`#3-implementierung--libmemory-policynix`](memory_oom.md#3-implementierung--libmemory-policynix) — 3. Implementierung — `lib/memory-policy.nix`
  - [`#api`](memory_oom.md#api) — API
  - [`#postgres-formel-32-gb--10g-max`](memory_oom.md#postgres-formel-32-gb--10g-max) — Postgres-Formel (32 GB → 10G Max)
- [`#4-p1-limits-implementiert`](memory_oom.md#4-p1-limits-implementiert) — 4. P1-Limits (implementiert)
- [`#4b-p2-limits-implementiert`](memory_oom.md#4b-p2-limits-implementiert) — 4b. P2-Limits (implementiert)
  - [`#was-ist-arr-helpernix`](memory_oom.md#was-ist-arr-helpernix) — Was ist `arr-helper.nix`?
- [`#5-system-baseline-nicht-in-memory-policynix`](memory_oom.md#5-system-baseline-nicht-in-memory-policynix) — 5. System-Baseline (nicht in memory-policy.nix)
- [`#6-backlog-p3`](memory_oom.md#6-backlog-p3) — 6. Backlog (P3+)
- [`#7-verifikation`](memory_oom.md#7-verifikation) — 7. Verifikation
- [`#8-regeln-fr-ki-nderungen`](memory_oom.md#8-regeln-fr-ki-nderungen) — 8. Regeln für KI-Änderungen
  - [`#niemals-ohne-user-freigabe`](memory_oom.md#niemals-ohne-user-freigabe) — NIEMALS (ohne User-Freigabe)
  - [`#immer`](memory_oom.md#immer) — IMMER
- [`#9-changelog`](memory_oom.md#9-changelog) — 9. Changelog

## migration-from-chats.md

- [`#homelab_server--grok--claude--deepseek`](migration-from-chats.md#homelab_server--grok--claude--deepseek) — homelab_server — Grok × Claude × DeepSeek
  - [`#thema-forward-auth--pocket-id`](migration-from-chats.md#thema-forward-auth--pocket-id) — Thema: Forward-Auth + Pocket-ID
  - [`#thema-cloudflare--geo`](migration-from-chats.md#thema-cloudflare--geo) — Thema: Cloudflare + Geo
  - [`#thema-blocky--caddy`](migration-from-chats.md#thema-blocky--caddy) — Thema: Blocky ↔ Caddy
  - [`#thema-streaming-jellyfin`](migration-from-chats.md#thema-streaming-jellyfin) — Thema: Streaming (Jellyfin)
  - [`#verworfen-homelab`](migration-from-chats.md#verworfen-homelab) — Verworfen (homelab)
  - [`#unraid-chats`](migration-from-chats.md#unraid-chats) — Unraid-Chats
  - [`#q958-ist-zustand-caddy-juni-2026`](migration-from-chats.md#q958-ist-zustand-caddy-juni-2026) — q958 Ist-Zustand (Caddy, Juni 2026)
- [`#stufe-5--caddy`](migration-from-chats.md#stufe-5--caddy) — Stufe 5 — Caddy
- [`#stufe-6--media`](migration-from-chats.md#stufe-6--media) — Stufe 6 — Media
  - [`#goldene-regeln-prompt-meta-kritik`](migration-from-chats.md#goldene-regeln-prompt-meta-kritik) — Goldene Regeln (Prompt-Meta-Kritik)
- [`#stufe-28--hardening`](migration-from-chats.md#stufe-28--hardening) — Stufe 2/8 — Hardening
- [`#bereits-richtig-deepseek-roast-obsolet`](migration-from-chats.md#bereits-richtig-deepseek-roast-obsolet) — Bereits richtig (DeepSeek-Roast obsolet)
- [`#bewusst-verworfen`](migration-from-chats.md#bewusst-verworfen) — Bewusst verworfen
- [`#duckdb--sqlite`](migration-from-chats.md#duckdb--sqlite) — DuckDB → SQLite

## ROADMAP.md

- [`#mynixos-v5-bernahme-grapefruit89mynixos-v5`](ROADMAP.md#mynixos-v5-bernahme-grapefruit89mynixos-v5) — mynixos-v5 Übernahme (grapefruit89/mynixos-v5)
- [`#legende`](ROADMAP.md#legende) — Legende
- [`#verworfen--nicht-wieder-aufgreifen`](ROADMAP.md#verworfen--nicht-wieder-aufgreifen) — Verworfen — nicht wieder aufgreifen
- [`#stufe-5--caddy`](ROADMAP.md#stufe-5--caddy) — Stufe 5 — Caddy
- [`#auth-matrix--wer-bekommt-was`](ROADMAP.md#auth-matrix--wer-bekommt-was) — Auth-Matrix — wer bekommt was?
- [`#vpn--usenet-stufe-6`](ROADMAP.md#vpn--usenet-stufe-6) — VPN — Usenet (Stufe 6)
- [`#stufe-6--media`](ROADMAP.md#stufe-6--media) — Stufe 6 — Media
- [`#stufe-8--nftables-geo--hrte`](ROADMAP.md#stufe-8--nftables-geo--hrte) — Stufe 8 — nftables (Geo + Härte)
  - [`#was-nftables-kann-arbeitstier`](ROADMAP.md#was-nftables-kann-arbeitstier) — Was nftables kann (Arbeitstier)
  - [`#was-nftables-nicht-kann`](ROADMAP.md#was-nftables-nicht-kann) — Was nftables NICHT kann
  - [`#erweiterungen-optional-stufe-8`](ROADMAP.md#erweiterungen-optional-stufe-8) — Erweiterungen (optional, Stufe 8+)
  - [`#cloudflare-falle`](ROADMAP.md#cloudflare-falle) — Cloudflare-Falle
  - [`#stufe-8-checkliste`](ROADMAP.md#stufe-8-checkliste) — Stufe-8 Checkliste
- [`#blocky--lan-dns-fr-alle-gerte`](ROADMAP.md#blocky--lan-dns-fr-alle-gerte) — Blocky — LAN-DNS für alle Geräte
- [`#stufe-9--production`](ROADMAP.md#stufe-9--production) — Stufe 9 — Production
- [`#wissens-ssot`](ROADMAP.md#wissens-ssot) — Wissens-SSoT
- [`#morgen--dringend-domain--cloudflare`](ROADMAP.md#morgen--dringend-domain--cloudflare) — Morgen — DRINGEND: Domain + Cloudflare
- [`#nchste-schritte-reihenfolge`](ROADMAP.md#nchste-schritte-reihenfolge) — Nächste Schritte (Reihenfolge)

## RUNBOOK.md

- [`#quick-ref`](RUNBOOK.md#quick-ref) — Schnellreferenz — alle bekannten Fehler
- [`#caddy`](RUNBOOK.md#caddy) — Caddy
  - [`#caddy-ip-mask`](RUNBOOK.md#caddy-ip-mask) — ip_mask Syntaxfehler → Endlosloop
- [`#arr-apps`](RUNBOOK.md#arr-apps) — Arr-Apps (Lidarr, Readarr, Sonarr, Radarr, Prowlarr)
  - [`#arr-env-missing`](RUNBOOK.md#arr-env-missing) — Fehlende .env-Datei
  - [`#arr-bindpaths`](RUNBOOK.md#arr-bindpaths) — BindPaths-Ziel fehlt
- [`#jellyfin`](RUNBOOK.md#jellyfin) — Jellyfin
  - [`#jellyfin-chown`](RUNBOOK.md#jellyfin-chown) — CAP_CHOWN fehlt im preStart
- [`#home-assistant`](RUNBOOK.md#home-assistant) — Home Assistant
  - [`#ha-corruption`](RUNBOOK.md#ha-corruption) — Core-Config-Korruption / KeyError
- [`#diagnose`](RUNBOOK.md#diagnose) — Diagnosebefehle — Schnellreferenz
- [`#siehe-auch`](RUNBOOK.md#siehe-auch) — Verwandt

## SECURITY.md

- [`#was-passiert-ist`](SECURITY.md#was-passiert-ist) — Was passiert ist
- [`#neues-repo-ab-init`](SECURITY.md#neues-repo-ab-init) — Neues Repo (ab init)
- [`#rotation-pflicht--alte-werte-waren-auf-github`](SECURITY.md#rotation-pflicht--alte-werte-waren-auf-github) — Rotation (Pflicht — alte Werte waren auf GitHub)
- [`#gitignore-regeln`](SECURITY.md#gitignore-regeln) — .gitignore-Regeln
- [`#dauerregeln`](SECURITY.md#dauerregeln) — Dauerregeln

## SESSION-2026-06-17-review-fixes.md

- [`#ausgangslage`](SESSION-2026-06-17-review-fixes.md#ausgangslage) — Ausgangslage
- [`#commit-35bf139--claude-review-findings-rev-001008`](SESSION-2026-06-17-review-fixes.md#commit-35bf139--claude-review-findings-rev-001008) — Commit `35bf139` — Claude Review Findings (REV-001–008)
  - [`#rev-008-high--kaputte-flake-konfigurationen`](SESSION-2026-06-17-review-fixes.md#rev-008-high--kaputte-flake-konfigurationen) — REV-008 (high) — Kaputte Flake-Konfigurationen
  - [`#impermanence-high-vor-stufe-9`](SESSION-2026-06-17-review-fixes.md#impermanence-high-vor-stufe-9) — Impermanence (high, vor Stufe 9)
  - [`#rev-002-medium--hardcoded-dev-passwort`](SESSION-2026-06-17-review-fixes.md#rev-002-medium--hardcoded-dev-passwort) — REV-002 (medium) — Hardcoded Dev-Passwort
  - [`#rev-004-medium--verify-no-secretssh`](SESSION-2026-06-17-review-fixes.md#rev-004-medium--verify-no-secretssh) — REV-004 (medium) — `verify-no-secrets.sh`
  - [`#rev-003-medium--restic-healthcheck`](SESSION-2026-06-17-review-fixes.md#rev-003-medium--restic-healthcheck) — REV-003 (medium) — Restic Healthcheck
  - [`#restic-s3-provision-fehlte-im-review`](SESSION-2026-06-17-review-fixes.md#restic-s3-provision-fehlte-im-review) — Restic S3-Provision (fehlte im Review)
  - [`#rev-001-medium--doc-drift`](SESSION-2026-06-17-review-fixes.md#rev-001-medium--doc-drift) — REV-001 (medium) — Doc-Drift
  - [`#rev-005-medium--legacy--duplikate-gelscht`](SESSION-2026-06-17-review-fixes.md#rev-005-medium--legacy--duplikate-gelscht) — REV-005 (medium) — Legacy / Duplikate gelöscht
  - [`#rev-006-low--firewall-host-werte`](SESSION-2026-06-17-review-fixes.md#rev-006-low--firewall-host-werte) — REV-006 (low) — Firewall-Host-Werte
  - [`#rev-007-low--restic-healthcheck-bei-fehler`](SESSION-2026-06-17-review-fixes.md#rev-007-low--restic-healthcheck-bei-fehler) — REV-007 (low) — Restic Healthcheck bei Fehler
- [`#commit-2d7af29--pre-rebuild-hardening`](SESSION-2026-06-17-review-fixes.md#commit-2d7af29--pre-rebuild-hardening) — Commit `2d7af29` — Pre-Rebuild Hardening
  - [`#restic-nur-mit-s3`](SESSION-2026-06-17-review-fixes.md#restic-nur-mit-s3) — Restic nur mit S3
  - [`#strikte-secrets-pflicht`](SESSION-2026-06-17-review-fixes.md#strikte-secrets-pflicht) — Strikte Secrets-Pflicht
  - [`#stufe-9-vorbereitet`](SESSION-2026-06-17-review-fixes.md#stufe-9-vorbereitet) — Stufe 9 vorbereitet
  - [`#rebuild-pipeline-verbessert-toolsrebuild-q958sh`](SESSION-2026-06-17-review-fixes.md#rebuild-pipeline-verbessert-toolsrebuild-q958sh) — Rebuild-Pipeline verbessert (`tools/rebuild-q958.sh`)
  - [`#git-hook`](SESSION-2026-06-17-review-fixes.md#git-hook) — Git-Hook
  - [`#weitere-bereinigung`](SESSION-2026-06-17-review-fixes.md#weitere-bereinigung) — Weitere Bereinigung
- [`#rebuild-ergebnis-17062026`](SESSION-2026-06-17-review-fixes.md#rebuild-ergebnis-17062026) — Rebuild-Ergebnis (17.06.2026)
- [`#bewusst-noch-offen`](SESSION-2026-06-17-review-fixes.md#bewusst-noch-offen) — Bewusst noch offen
- [`#ntzliche-befehle`](SESSION-2026-06-17-review-fixes.md#ntzliche-befehle) — Nützliche Befehle
- [`#referenzen`](SESSION-2026-06-17-review-fixes.md#referenzen) — Referenzen

## SPEC_REGISTRY.md

- [`#kern-bibliotheken`](SPEC_REGISTRY.md#kern-bibliotheken) — Kern-Bibliotheken
- [`#policy-module`](SPEC_REGISTRY.md#policy-module) — Policy-Module
- [`#gateway--policy`](SPEC_REGISTRY.md#gateway--policy) — Gateway & Policy
- [`#media--apps`](SPEC_REGISTRY.md#media--apps) — Media & Apps
- [`#dns-hostnamen-ssot`](SPEC_REGISTRY.md#dns-hostnamen-ssot) — DNS-Hostnamen (SSOT)
- [`#neue-eintrge`](SPEC_REGISTRY.md#neue-eintrge) — Neue Einträge

## unraid-migration-map.md

- [`#core-muss-laufen`](unraid-migration-map.md#core-muss-laufen) — Core (MUSS laufen)
- [`#media-frontend`](unraid-migration-map.md#media-frontend) — Media Frontend
- [`#media-backend-arr`](unraid-migration-map.md#media-backend-arr) — Media Backend (*arr)
- [`#ai`](unraid-migration-map.md#ai) — AI
- [`#tools-gestoppt-auf-unraid`](unraid-migration-map.md#tools-gestoppt-auf-unraid) — Tools (gestoppt auf Unraid)
- [`#netzwerk-mapping`](unraid-migration-map.md#netzwerk-mapping) — Netzwerk-Mapping
- [`#migrations-reihenfolge`](unraid-migration-map.md#migrations-reihenfolge) — Migrations-Reihenfolge
- [`#volumes-unraid--q958-storage`](unraid-migration-map.md#volumes-unraid--q958-storage) — Volumes (Unraid → q958 Storage)
