---
meta:
  role: doc
  purpose: Zero-Trust Provenance — Inspirationsquellen und bewusste Nicht-Abhängigkeiten
  tags:
    - governance
    - provenance
    - sources
---

# SOURCES — Provenance Tracking

> Inspiriert von `SOURCES.md` aus mynixos-v5 (Zero-Trust Provenance Pattern):  
> "Wir dokumentieren intellektuelle Quellen statt Runtime-Abhängigkeiten zu erzeugen."

---

## Philosophie

Nix-Grok importiert **keine** externen Flake-Inputs außer nixpkgs und home-manager.  
Ideen und Patterns kommen von außen — als Inspiration, nicht als Dependency.

---

## Architektur-Inspirationen

| Quelle | Was übernommen | Was bewusst NICHT übernommen |
|--------|---------------|------------------------------|
| **mynixos-v5** (eigenes Vorgänger-Repo) | ABC Storage Tiering, UID-Egress-Control, No-Legacy Policy | NIXMETA-Format, flake-parts, IFD-Konstrukte |
| **mynixos** (erstes Repo) | Policy-Layer-Konzept (90-policy/), Kernel-Blacklisting | flat-layout-Assertion (Nix-Grok hat Unterordner by design) |
| **Misterio77/nix-config** | Impermanence-Ansatz (tmpfs-root), systemd-hardening-Patterns | Home-Manager-Zentriertheit |
| **nix-mineral** | Kernel-Hardening Checkliste (Blacklists, sysctl-Patterns) | Standalone-Modul (zu viel Overhead) |
| **NixOS-Hardening Community** | Systemd-Service-Härtung (ReadWritePaths, CapabilityBoundingSet) | Automatische Assertions-Generatoren |

---

## DNS & Netzwerk

| Thema | Entscheidung | Abgelehnte Alternative |
|-------|-------------|------------------------|
| DNS-Resolver | Technitium (DoT, fail-closed) | Blocky (fail-open Bug, ADR-001) |
| Firewall | nftables nativ | iptables, ufw (ADR-008) |
| VPN (Admin) | Netbird (self-hosted) | Tailscale (DNS-Konflikte bei v5) |
| VPN (Usenet) | Privado WireGuard | OpenVPN (overhead) |

---

## Storage

| Komponente | Gewählt | Abgelehnt |
|-----------|---------|-----------|
| Pool-Aggregation | MergerFS (Tier B+C) | ZFS (ECC-Pflicht, Lizenz), Btrfs RAID (zu komplex) |
| Persistentes Dateisystem | ext4 | ZFS, reiserfs, ext2/3 |
| Backup | Restic → S3 | Kopia (Community-Feedback), borg (kein S3-nativ) |
| Archivierung | HDD Tier-C | Cloud-only (Datensouveränität) |

---

## Ingress & Security

| Komponente | Gewählt | Abgelehnt |
|-----------|---------|-----------|
| Reverse Proxy | Caddy (auto-TLS) | nginx (kein auto-TLS), Traefik (Docker-zentriert) |
| SSO | Pocket-ID (OIDC) | Authelia (heavy), Keycloak (Java, resource-heavy) |
| Secrets | SOPS + age | Vault (Server-Overhead), environment files plaintext |
| Cert-Mgmt | Caddy ACME-intern | cert-manager (Kubernetes-heritage) |
| Transport | Unix Domain Sockets first | TCP-Loopback (ADR-019) |

---

## Observability

| Komponente | Gewählt | Abgelehnt |
|-----------|---------|-----------|
| Metriken | VictoriaMetrics | Prometheus (mehr RAM, weniger Features) |
| Logs | Loki + Vector | ELK (Java-Overhead, Lizenz) |
| Dashboards | Grafana | Netdata (Cloud-Pflicht für erweiterte Features) |
| Health-Check | Gatus | UptimeKuma (Docker-zentriert) |

---

## Nicht-Abhängigkeiten (bewusste Lücken)

Diese Flake-Inputs wurden geprüft und **bewusst nicht aufgenommen:**

| Kandidat | Warum abgelehnt |
|----------|----------------|
| `flake-parts` | Meta-Framework-Overhead, reines Nix reicht (ADR-013) |
| `nixarr` / `nixflix` | Versions-Drift, nicht im Nix-Grok-Kontroll-Pfad |
| `lanzaboote` | Lockout-Risiko ohne ECC-Hardware-Setup |
| `nix-mineral` | Standalone-Import widerspricht dendritischer Architektur |
| `home-manager` | Nur bei Bedarf, nicht als Pflicht-Input |

---

---

## Repo-Genealogie: Lessons Learned

Drei Vorgänger-Repos wurden analysiert. Einmal gewonnenes Wissen wurde in ADRs und Guides überführt.

| Repo | URL | Gewonnene Erkenntnisse | Status |
|------|-----|----------------------|--------|
| `mynixos` (v1) | github.com/grapefruit89/mynixos | No-Legacy-Philosophie (ADR-020) | vollständig migriert |
| `mynixos-v5` | github.com/grapefruit89/mynixos-v5 | Antipatterns, IFD-Verbot, SOURCES-Konzept | vollständig migriert |
| `mynixos-knowledge-base` | github.com/grapefruit89/mynixos-knowledge-base | SOPS-Boot-Race (ADR-021), No-RAID (ADR-022), SSH Socket-Aktivierung ANTIPATTERN, No-GUI-Assertion | vollständig migriert |
| `nix-hermes` | github.com/grapefruit89/nix-hermes | `LLM_FIRST_INSTRUCTIONS.md`-Muster (Nix-Grok ist bereits weiter mit nixos_docs.sqlite + MCP) | konzeptuell übernommen |

### Hinweis zu nix-hermes

Eine externe KI-Analyse beschrieb `build_db.js`, `nixos_docs.db` und `mcp_config.json` als implementiert in `nix-hermes`. **Das ist falsch** — diese Artefakte existieren nicht im Repo. `LLM_FIRST_INSTRUCTIONS.md` beschreibt nur eine Bauanleitung für eine KI. Nix-Grok hat mit `nixos_docs.sqlite` + FTS5 + MCP-Server diese Architektur bereits produktiv übertroffen.

*Letzte Aktualisierung: 2026-06-30*  
*Nächste Review: Bei neuem Flake-Input oder Architektur-Entscheidung*
