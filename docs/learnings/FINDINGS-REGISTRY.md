# FINDINGS-REGISTRY — Nix-Grok Befund-Provenance

> Jeder externe Befund der in Nix-Grok übernommen wird, bekommt hier einen Eintrag.
> Format: Was gefunden → Woher → Was damit gemacht → Datum.
>
> Unterschied zu `SOURCES.md`: SOURCES.md dokumentiert *Inspirations-Repos* auf hoher Ebene.
> Hier stehen *spezifische Befunde* mit direktem Nix-Grok-Impact.

---

## Aktive Einträge

| ID | Befund | Quelle | Aktion | Datum | Status |
|----|--------|--------|--------|-------|--------|
| F-001 | SOPS Boot-Race mit Impermanence: `sshKeyPaths` muss auf Persist-Pfad zeigen, nicht Bind-Mount | knowledge-base/adr/ADR-016-Sops-Boot-Timing.md | `05-sops.nix` conditional sshKeyPaths + sops-install-secrets ordering; `docs/adr/021-sops-impermanence-boot-timing.md` | 2026-06-30 | ✅ implementiert |
| F-002 | SSH Socket-Aktivierung: Niemals SSH socket-aktivieren — Aussperr-Risiko überwiegt ~5MB RAM | knowledge-base/adr/ADR-012-Socket-Activation-Selection.md | `docs/guides/ANTIPATTERNS.md` — neuer Eintrag | 2026-06-30 | ✅ dokumentiert |
| F-003 | No-GUI Build-Assertion: Build soll fehlschlagen wenn X11/GNOME/KDE aktiviert | knowledge-base/adr/ADR-010-Headless-Server-Law.md | `lib/forbidden-tech.nix` POL-FT-006/007/008 | 2026-06-30 | ✅ implementiert |
| F-004 | Anti-RAID / Distance-Parity-Mandate: Geografische Redundanz > lokales RAID | knowledge-base/adr/ADR-015-Distance-Parity-Mandate.md | `docs/adr/022-no-raid-distance-parity.md` | 2026-06-30 | ✅ dokumentiert |
| F-005 | Dropbear Rescue SSH: Sekundärer SSH-Daemon auf Port 2222, unabhängig von OpenSSH | nix-hermes/ADR/ADR-23-dropbear-rescue.md | Bereits implementiert in Nix-Grok (`20-security.nix`, `erstAb 8`) — kein Handlungsbedarf | 2026-06-30 | ✅ bereits vorhanden |
| F-006 | No-Legacy-Stack: Explizite Verbote für GRUB, cron, NetworkManager, iptables | mynixos-v5 | `docs/adr/020-no-legacy-explicit-stack.md` | 2026-06-30 | ✅ dokumentiert |
| F-007 | IFD-Verbot (Import-From-Derivation) verlangsamt `nix eval` und `dry-build` | mynixos-v5 | `docs/guides/ANTIPATTERNS.md` + `lib/forbidden-tech.nix` (implizit via dry-build-gate) | 2026-06-30 | ✅ dokumentiert |
| F-008 | SQLite-Temp-Dateien (.wal/.shm/.journal) beim Storage-Mover ausschließen | eigene Analyse | `modules/30-storage/30-storage.nix` — rclone excludes | 2026-06-30 | ✅ implementiert |
| F-009 | learnings/-Ordner als Retrospektiv-Layer: Trennung von ADR (Entscheidung) vs. Audit (Befund) | knowledge-base/learnings/ Struktur | Dieser Ordner | 2026-06-30 | ✅ implementiert |

---

## Offene / zukünftige Befunde

| ID | Befund | Quelle | Nächste Aktion |
|----|--------|--------|----------------|
| F-010 | .nix-Dateien in nixos_docs.sqlite indexieren — aktuell nur Markdown | nix-hermes/LLM_FIRST_INSTRUCTIONS.md | MCP-Server erweitern um `.nix`-Dateien per SQL querybar zu machen |
| F-011 | FINDINGS-REGISTRY als Pre-Commit-Hook: Neue externe Abhängigkeit ohne Registry-Eintrag schlägt fehl | knowledge-base Prozess-Standard | Optional: Shell-Hook der auf imports ohne F-xxx Referenz prüft |

---

## Prozess

1. Befund entdeckt → hier eintragen (Entwurf, Status: 🔍 geprüft)
2. Entscheidung für/gegen Übernahme → Status: ✅ implementiert / ❌ abgelehnt / 🔄 verschoben
3. Wenn übernommen: Referenz in Code-Kommentar oder ADR setzen

