---
meta:
  role: doc
  purpose: ADR-2029 mTLS Zero-Trust — interne Dienst-Kommunikation (proposed, nicht implementiert)
  status: proposed
  date: 2026-07-05
  error_pattern: "certificate verify failed|tls.*handshake.*error|x509.*unknown authority"
  quick_fix: "step certificate inspect <cert.pem>; curl -v --cacert /run/secrets/ca.crt https://dienst.internal"
  services: []
  betrifft: []
  docs:
    - docs/adr/2026-kernel-hardening-sysctl.md
    - docs/adr/028-systemd-service-isolation.md
    - docs/adr/1004-unix-socket-upstreams.md
    - docs/adr/1019-uds-first-philosophy.md
  tags:
    - adr
    - mtls
    - zero-trust
    - networking
    - proposed
---

# ADR-2029: mTLS Zero-Trust — Interne Dienst-Kommunikation {#adr-2029}

| Feld | Wert |
|------|------|
| **Status** | **proposed** (nicht implementiert) |
| **Datum** | 2026-07-05 |
| **Host** | q958 |
| **Entscheider** | Betreiber (Moritz) |

---

> ⚠️ **Dieses ADR ist proposed — kein Code existiert dafür. Es dokumentiert die Architektur-Intention für eine zukünftige Implementierung.**

## Kontext {#kontext}

- Aktuell kommunizieren interne Dienste primär über Unix-Domain-Sockets ([ADR-1004](1004-unix-socket-upstreams.md), [ADR-1019](1019-uds-first-philosophy.md)) — sicher und effizient für Same-Host-Kommunikation.
- UDS reicht nicht für Multi-Host-Szenarien oder containerisierte Dienste auf separaten Netbird-Nodes.
- Das "weicher Kern"-Problem: Wenn ein Dienst aus einer Sandbox ausbricht, könnte er intern andere Dienste direkt über TCP ansprechen, ohne weitere Authentifizierung.
- Interne HTTP-Endpunkte (Servarr-APIs, Prometheus, etc.) sind derzeit nur über nftables-Regeln geschützt — kein kryptografischer Identitätsnachweis.

## Entscheidung (proposed) {#entscheidung}

**Gegenseitige TLS-Authentifizierung (mTLS) für alle internen TCP-Verbindungen, die das UDS-Modell verlassen müssen.**

### Private CA (step-ca) {#private-ca}

```nix
# Geplante Implementierung
services.step-ca = {
  enable = true;
  address = "127.0.0.1";
  port = 8443;
  settings = {
    dnsNames = [ "ca.internal.q958" ];
  };
};
```

Jeder Microservice und jede Sandbox erhält ein individuelles Zertifikat, ausgestellt von der privaten CA. Gültigkeit: 24 Stunden (Auto-Rotation via ACME-ähnlichem Step-Client).

### mTLS-Konfiguration (Caddy) {#mtls-caddy}

```caddy
# Geplant: interne Dienst-zu-Dienst-Routen mit mTLS
prowlarr.internal:443 {
  tls {
    client_auth {
      mode require_and_verify
      trusted_ca_cert_file /run/secrets/internal-ca.crt
    }
  }
  reverse_proxy unix//run/prowlarr/prowlarr.sock
}
```

### Zertifikat-Bereitstellung {#zertifikat-bereitstellung}

Zertifikate werden über `systemd-creds` ([ADR-2024](2024-systemd-creds-tpm.md)) oder ein `step`-Sidecar-Service pro Dienst bereitgestellt. Die privaten Keys landen nie im Nix-Store.

## Warum noch nicht implementiert {#noch-nicht}

- UDS-first ([ADR-1019](1019-uds-first-philosophy.md)) deckt >90 % der internen Kommunikation ab — mTLS-Overhead wäre unverhältnismäßig.
- `step-ca` als NixOS-Service braucht persistenten State und CA-Key-Management — Komplexität noch nicht gerechtfertigt.
- Netbird (Tailscale-Mechanismus) bietet bereits E2E-Verschlüsselung für Multi-Host-Kommunikation.
- **Trigger für Implementierung:** Sobald ein Dienst außerhalb des UDS-Perimeters Dienste ohne menschliche Authentifizierung aufrufen muss (Agent-zu-Agent über Netzwerk).

## Alternativen verworfen {#alternativen}

- **Keine Authentifizierung intern** — Verletzt Zero-Trust-Prinzip. Akzeptabel solange UDS dominiert, kritisch bei Netzwerk-IPC.
- **IP-basierte ACLs (nftables)** — Kein kryptografischer Identitätsnachweis; IP-Spoofing möglich im Containernetz. Ergänzend, nicht hinreichend.
- **Service-Mesh (Consul Connect, Istio)** — Viel zu komplex für Homelab. Abgelehnt.

## Nächste Schritte {#naechste-schritte}

1. `step-ca` als NixOS-Service evaluieren und testen
2. Ein Pilot-Dienst (z. B. Prometheus → Gatus) mit mTLS ausrüsten
3. Zertifikat-Rotation via systemd-Timer sicherstellen
4. ADR-Status auf `accepted` setzen und Code in `betrifft` eintragen

## Changelog {#changelog}

| Datum | Änderung |
|-------|----------|
| 2026-07-05 | Initial (proposed, aus Grok-Systemanalyse) |

## Siehe auch {#siehe-auch}

- [ADR-1004 — Unix-Socket-Upstreams](1004-unix-socket-upstreams.md) — aktuelle primäre IPC-Methode
- [ADR-1019 — UDS-First-Philosophie](1019-uds-first-philosophy.md) — warum UDS fast immer genug ist
- [ADR-2024 — systemd-creds TPM](2024-systemd-creds-tpm.md) — Secret-Bereitstellung für Zertifikat-Keys
- [ADR-2026 — Kernel-Härtung](2026-kernel-hardening-sysctl.md) — komplementäre Härtungsschicht
- [ADR-028 — Systemd Service Isolation](028-systemd-service-isolation.md) — Sandbox-Ebene unter mTLS
