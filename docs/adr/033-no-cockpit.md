---
meta:
  role: doc
  purpose: Kein Cockpit — Angriffsfläche überwiegt Nutzen im Ein-Personen-Homelab
  status: accepted
  date: 2026-07-06
  tags:
    - security
    - admin-ui
    - attack-surface
---

# ADR-033: Kein Cockpit — Angriffsfläche überwiegt Nutzen

## Kontext

Cockpit (Port 7003, `services.cockpit`) war als Web-basiertes Server-Admin-UI geplant
und in der Codebase als reservierter Port, Modul (`modules/60-apps/forge.nix`),
Service-Spec und DNS-Eintrag vorbereitet — aber **nie aktiviert** (`enable` wurde
in keinem `rollout.nix` je auf `true` gesetzt).

Der Wert wurde im Rahmen eines Layer-Reviews (20-security + Grok-Analyse) bewertet:

> *"Cockpit: Mehr Angriffsfläche als Nutzen für einen Ein-Personen-Homelab."*

## Entscheidung

Cockpit wird **vollständig entfernt**:

- Port 7003 aus `08-ports.nix` gestrichen
- `modules/60-apps/forge.nix` gelöscht (war ausschließlich Cockpit + KVM-Machines)
- Referenzen aus `services-spec.nix`, `dns-map.nix`, `server-map.nix`,
  `service-enable.nix`, `gatus-endpoints.nix`, `machines/q958/default.nix` entfernt

## Begründung

**Warum Cockpit nicht passt**:

1. **Angriffsfläche**: Cockpit öffnet einen zusätzlichen Web-Daemon auf dem Host.
   Selbst hinter SSO (Pocket-ID) oder Tailscale ist jede neue HTTP-Schnittstelle ein
   potenzieller Angriffsvektor — insbesondere da Cockpit privilegierten Zugriff
   auf systemd, Netzwerk und Dateisystem hat.

2. **Single-Operator**: Der Homelab wird von einer Person verwaltet. Der Mehrwert
   eines grafischen Admin-UIs gegenüber SSH + NixOS-Deklaration ist marginal.

3. **Widerspruch zum deklarativen Ansatz**: Cockpit-Actions (Dienste starten/stoppen,
   Netzwerk ändern) erzeugen imperativem State außerhalb des Nix-Rebuilds —
   genau das, was dieses Projekt systematisch vermeidet (vgl. GUIDE-declarative-mindset).

4. **Nie aktiviert**: Die Reservierung war spekulativ. Kein produktiver Use-Case
   ist eingetreten.

**Was stattdessen**:

- Administration via SSH + `nixos-rebuild` (deklarativ, auditierbar)
- Grafana + Gatus für Observability
- Für spätere Visualisierung: `pkgs.nixosOptionsDoc` als statische HTML-Referenz
  (keine Runtime-Angriffsfläche, rein build-time)

## Alternativen verworfen

| Alternative | Warum verworfen |
|-------------|----------------|
| Cockpit nur via Tailscale | Reduziert Angriffsfläche, löst aber nicht den Widerspruch zum deklarativen Ansatz |
| Cockpit read-only | Cockpit hat keine sinnvolle Read-only-Mode — privilegierter Daemon bleibt |
| Cockpit mit mTLS | Overengineering (ADR-2029 reserviert mTLS für Zero-Trust-Szenarien, nicht für interne Tools) |

## Konsequenzen

- Port 7003 ist frei (kann bei Bedarf für anderes vergeben werden)
- `KVM/libvirtd` kann bei Bedarf ohne Cockpit aktiviert werden (eigenes Modul)
- Intel AMT Proxy-Konfiguration (`machines.domain`) entfällt — AMT-Zugriff weiterhin
  direkt über `192.168.1.100:16992` im LAN möglich
