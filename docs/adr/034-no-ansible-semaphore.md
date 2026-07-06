---
meta:
  id: ADR-034
  title: Kein Ansible/Semaphore — Imperativismus verboten
  status: accepted
  date: 2026-07-06
  layer: 00-core (Policy)
  tags:
    - policy
    - declarative
    - forbidden-tech
---

# ADR-034: Kein Ansible/Semaphore — Imperativismus verboten

## Kontext

Semaphore (Ansible-UI, Port 7002) war in der Codebase als geplanter Dienst
reserviert (`lib/server-map.nix`, `meta/index.yaml`). Ein Code-Review (Juli 2026)
hat die Reservierung aufgedeckt und zur Entscheidung geführt.

**Was ist Semaphore?**
Semaphore ist ein Web-Frontend für Ansible-Playbooks — ein grafisches Tool um
imperative Shell-Skripte (`ansible-playbook`) gegen entfernte Hosts auszuführen.

## Entscheidung

Semaphore und jede Form von Ansible-basierter Konfigurationsverwaltung sind
**dauerhaft verboten** und durch eine Assertion in `lib/forbidden-tech.nix`
(POL-FT-009) erzwungen.

Referenzen wurden bereinigt:
- `lib/server-map.nix` (Port 7002 / `70-forge`-Eintrag)
- `lib/unix-sockets.nix` (Kommentar)
- Port 7002 bleibt reserviert-frei (kein anderer Dienst weist auf diesen Port)

## Begründung

**Grundsatzproblem — Paradigma-Kollision**:

NixOS ist **deklarativ**. Ansible ist **imperativ**. Beide gleichzeitig zu verwenden
erzeugt zwangsläufig Drift zwischen dem was Nix konfiguriert und dem was Ansible
verändert hat — und dieser Drift ist für Menschen und Agenten unsichtbar.

| Eigenschaft | NixOS (deklarativ) | Ansible (imperativ) |
|------------|-------------------|-------------------|
| Wahrheitsquelle | `/etc/nixos` im Git | Playbooks + tatsächlicher Host-State |
| Reproduzierbarkeit | Garantiert | Nicht garantiert |
| State-Drift | Unmöglich (Rebuild überschreibt) | Jede Aktion hinterlässt Drift |
| Rollback | `nixos-rebuild` zur alten Generation | Manuell / unsicher |
| Audit | Git-History | Ansible-Log (falls aktiv) |

**Warum Semaphore speziell nicht**:

1. **Doppelung**: Alles was Ansible kann, kann NixOS deklarativer und sicherer.
2. **Attack Surface**: Web-UI mit `sudo`-Zugriff auf den Host (noch schlimmer als Cockpit).
3. **Widerspruch zum Mindset**: Änderungen via Semaphore umgehen den Rebuild-Workflow
   (`scripts/nixos-rebuild-safe.sh`) und das Pre-commit-Gate.
4. **Nie gebraucht**: Die Reservierung war spekulativ, kein Use-Case ist eingetreten.

## Folgen

- `lib/forbidden-tech.nix` → `[POL-FT-009]`: Build bricht wenn `services.semaphore.enable = true`
- Die Entscheidung gilt global für alle Maschinen die dieses Flake nutzen
- KVM/Libvirtd kann ohne Ansible-Overhead direkt via NixOS aktiviert werden

## Alternative

Für Automatisierung: `systemd.services` + `scripts/` + `nixos-rebuild switch`.
Das ist deklarativ, auditierbar und von NixOS verwaltet.
