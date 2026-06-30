# ADR-021: SOPS Boot-Timing mit Impermanence — Race-Condition-Schutz

**Status:** Accepted (Vorarbeit für Stufe 9)  
**Datum:** 2026-06-30  
**Quelle:** Knowledge-Base ADR-016, 05-sops.nix Zeile 118

---

## Kontext

Wenn `sops-nix` und `Impermanence` (tmpfs-Root) gleichzeitig aktiv sind (ab Stufe 9), entsteht eine mögliche Boot-Timing-Race:

- `sops-install-secrets.service` benötigt den Age-SSH-Schlüssel zur Entschlüsselung
- Der SSH-Host-Key liegt auf `/persist/etc/ssh/ssh_host_ed25519_key` (persistente Partition)
- `/etc/ssh/ssh_host_ed25519_key` ist ein **Bind-Mount** von `/persist/etc/ssh/ssh_host_ed25519_key`
- Bind-Mounts sind `fileSystems`-Einträge und werden von `local-fs.target` abgedeckt
- Wenn `sops-install-secrets.service` early-boot-systemd früher als `local-fs.target` startet → Schlüssel nicht gefunden → Boot schlägt fehl

**Konsequenz ohne Fix:** Nach einem vollständigen Root-FS-Wipe (Impermanence) kann das System nicht ohne manuelle Intervention booten.

## Entscheidung

Zwei Maßnahmen in `modules/00-core/05-sops.nix`:

### 1. Persistenten Pfad für sshKeyPaths verwenden

```nix
age.sshKeyPaths = [
  (
    if config.my.impermanence.enable
    then "${config.my.impermanence.persistMountPoint}/etc/ssh/ssh_host_ed25519_key"
    else "/etc/ssh/ssh_host_ed25519_key"
  )
];
```

Der direkte Pfad zur persistenten Partition umgeht die Bind-Mount-Abhängigkeit komplett.

### 2. Explizite systemd-Ordering für sops-install-secrets

```nix
systemd.services.sops-install-secrets = lib.mkIf config.my.impermanence.enable {
  after = [ "local-fs.target" "<persist-mountpoint>.mount" ];
};
```

## Alternativen verworfen

- **Bind-Mount-Pfad verwenden ohne Ordering** — implizite Abhängigkeit über `local-fs.target`, fragil bei Edge-Cases wie failed mounts oder initrd-Weiterleitung
- **SOPS auf Stufe 10+ verschieben** — unnötig; der Fix ist klein und löst das Problem sauber

## Status in Nix-Grok

Beide Fixes sind in `05-sops.nix` implementiert (Commit 2026-06-30). Aktiv wird die Logik erst ab Stufe 9 (`lib.mkIf config.my.impermanence.enable`).

## Links

- `modules/00-core/05-sops.nix` — Implementierung
- `machines/q958/rollout.nix` — `my.impermanence.enable = erstAb 9`
- Knowledge-Base `adr/ADR-016-Sops-Boot-Timing.md` — Originalfund
