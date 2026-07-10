---
meta:
  role: doc
  purpose: Verbotene Muster — Synthese aus nix-hermes Guides
  date: 2026-07-10
  status: current
  docs:
    - docs/adr/007-dendritic-one-file-per-service.md
    - docs/adr/012-modern-cli-tools.md
    - docs/adr/1004-unix-socket-upstreams.md
    - docs/adr/2008-nftables-l4-hardening.md
    - docs/adr/2024-systemd-creds-tpm.md
  tags:
    - antipattern
    - architecture
---

# Antipatterns {#antipatterns}

> Explizit **nicht** im q958-Repo — portiert aus nix-hermes `Guides/ANTIPATTERN-*`.

## sops-nix / agenix für single-host-Setups {#sops-nix}

`sops-nix` oder `agenix` als Secret-Management für q958 (single-host, rotierbare Keys).

**Warum nicht:**
- Der einzige echte Vorteil (verschlüsselte Secrets versionierbar im Git, Multi-Host-Sharing) ist für q958 **wertlos** — ein Host, Secrets nicht im Repo.
- `age.keys.txt` / SSH-Decryption-Key liegt lesbar auf Disk — wer ihn hat, hat alle Secrets.
- `sops-nix` ist ein Flake-Input: externe Dependency für null echten Sicherheitsgewinn.
- Boot-Timing-Komplexität mit Impermanence (ADR-2021, jetzt withdrawn).
- Nix-Store-Leak-Risiko: sops-Pfade und Strukturen fließen durch die Evaluierung.

**Stattdessen:** `my.creds` (systemd-creds) — kein Flake-Input, kein Key auf Disk (TPM),
automatisches Credential-Cleanup durch systemd. Assertion in `05-creds.nix` verhindert
versehentliches Aktivieren von sops-nix im Repo.

Siehe [ADR-2024 — systemd-creds + TPM2](../adr/2024-systemd-creds-tpm.md).

## Legacy iptables-Firewall {#iptables}

`networking.firewall.enable = true` (iptables-Backend) statt nativem nftables.  
**Stattdessen:** `modules/15-firewall.nix` + `lib/nftables-rules.nix` — siehe [ADR-2008](../adr/2008-nftables-l4-hardening.md) und [GUIDE-nftables-hardening](GUIDE-nftables-hardening.md).

## Externe Media-Flakes (Nixarr/Nixflix als Input) {#media-flakes}

Flake-Inputs für *arr-Stacks erzeugen Versions-Drift und widersprechen AGENTS.md.  
**Stattdessen:** native Module in `modules/50-media/`, Sync-Logik in `sync-script.sh` — [ADR-007](../adr/007-dendritic-one-file-per-service.md).

## Socat-UDS-Bridges für Caddy {#socat-uds}

Umweg über TCP statt Unix-Socket-Upstreams.  
**Stattdessen:** [ADR-1004 — Unix-Socket-Upstreams](../adr/1004-unix-socket-upstreams.md).

## Kopia statt Restic {#kopia}

**Stattdessen:** `services.restic.backups` in `30-storage.nix` — [GUIDE-data-management.md](GUIDE-data-management.md).

## Thymis / NIXMETA-Auto-Import {#nixmeta}

Automatische Modul-Discovery aus Kommentar-Headern — Build-Kosten und Magic.  
**Stattdessen:** explizite Imports in `machines/q958/default.nix`, File-Meta nur für KI-Index ([ADR-007](../adr/007-dendritic-one-file-per-service.md)).

## SSH-Rescue auf Production-Port {#ssh-rescue}

Rescue-SSH auf demselben Port wie Production-SSH.  
**Stattdessen:** Dropbear 2222, Production 53844 (Stufe 9) — [GUIDE-security-secrets.md#notfall](GUIDE-security-secrets.md#notfall).

## Logs auf tmpfs ohne Journal-Persist {#tmpfs-logs}

Bei Impermanence Journal verlieren.  
**Stattdessen:** bind-mount `/var/log/journal` → `/persist/var/log/journal` ([GUIDE-storage-tiers.md#impermanence](GUIDE-storage-tiers.md#impermanence)).

## Bastelmodus (imperative Overrides) {#bastelmodus}

`nix-env`, manuelle `/etc`-Edits, `systemctl edit` ohne Nix-Commit.  
**Stattdessen:** `rollout.stufe` erhöhen, rebuild, testen ([ADR-012](../adr/012-modern-cli-tools.md)).

## User-Agent Jellyfin-Bypass {#jellyfin-bypass}

Unsicher und fragil.  
**Stattdessen:** `X-Emby-Authorization` Regex in `jellyfin.nix`.


## Docker / OCI-Runtime {#docker}

Installierte Docker-Daemon (`services.docker.enable = true`) oder Docker Compose auf dem Host.  
**Warum nicht:** Verletzt NixOS-Immutabilität — Docker verwaltet eigene FS-Layer außerhalb des Nix-Store. Container-State ist nicht deklarativ, OCI-Images sind kein Nix-Input.  
**Stattdessen:** `services.<name>` NixOS-Module. Für Container die kein Nix-Modul haben: `virtualisation.oci-containers` — aber mit Bedacht und als Ausnahme.

## Cloudflare Orange Cloud (Proxy-Modus) {#cf-orange-cloud}

Cloudflare im Proxy-Modus (orange Wolke) vor echten Web-Diensten.  
**Warum nicht:** Verletzt Cloudflare ToS für nicht-HTTP-Traffic; echte IP-Adressen werden von Cloudflare gesehen und gespeichert; man verliert TLS-Endpunkt-Kontrolle.  
**Stattdessen:** DNS-only Grau-Wolke. Caddy terminiert TLS direkt. Geoblock und Rate-Limiting in nftables/Caddy lokal.

## ZFS auf Consumer-Hardware {#zfs}

ZFS auf Heimserver-Hardware (SATA-HDDs, kein ECC-RAM, kein Hardware-RAID).  
**Warum nicht:** ZFS benötigt ECC-RAM für zuverlässige Checksums. Auf Consumer-Hardware führt RAM-Fehler zu Silent Data Corruption. Lizenz (CDDL) ist inkompatibel mit GPL-Kernel-Integration.  
**Stattdessen:** ext4 für persistente Partitionen, MergerFS für Pool-Aggregation (Tier B/C), keine RAID-Simulation.

## flake-parts / Modular Flake Frameworks {#flake-parts}

`flake-parts`, `flake-utils`, `flake-compat` oder ähnliche Meta-Flake-Frameworks.  
**Warum nicht:** Externe Framework-Dependency für etwas das reines Nix kann. Build-Verhalten und Evaluation hängen dann von Framework-Versionen ab.  
**Stattdessen:** Reines Flake (`flake.nix` direkt), keine external Abstraktionsschicht — [ADR-013](../adr/013-flake-portability.md).

## SSH mit Passwort-Authentifizierung {#ssh-password}

`services.openssh.settings.PasswordAuthentication = true`.  
**Warum nicht:** Passwörter sind Brute-Force-angreifbar. Jeder kompromittierte Client mit einem gespeicherten Passwort gibt Zugang.  
**Stattdessen:** Ausschließlich `AuthorizedKeysFile` mit Ed25519-Keys. `PermitRootLogin = "no"`.

## Secure Boot via Lanzaboote {#lanzaboote}

`boot.lanzaboote.enable = true` (Secure Boot mit eigenem Schlüssel).  
**Warum nicht:** Lockout-Risiko bei UEFI-Firmware-Update oder fehlerhafter Schlüssel-Rotation. Recovery ohne physischen Zugriff nicht möglich. Im Homelab-Kontext bringt Secure Boot wenig Sicherheitsvorteil gegenüber dem Risiko.  
**Stattdessen:** systemd-boot ohne Secure Boot. TPM2-basierte Disk-Verschlüsselung als Alternative.

## Import-From-Derivation (IFD) {#ifd}

`builtins.readFile (pkgs.someDerivation + "/file")` oder ähnliche IFD-Konstrukte in Modul-Code.  
**Warum nicht:** IFD erzwingt Derivation-Build während der Nix-Evaluierung — das macht `nix eval`, `nix flake check` und alle reinen Evaluierungsschritte langsam. `nixos-rebuild dry-build` baut plötzlich Dinge.  
**Stattdessen:** Werte zur Evaluierungszeit berechnen (reines Nix), oder als `pkgs.writeText`/`pkgs.runCommand` Derivation explizit in `config` setzen.

## mTLS für Admin-Zugriff {#mtls-admin}

Mutual TLS (Client-Zertifikate) für interne Admin-Interfaces (Cockpit, Grafana-Admin etc.).  
**Warum nicht:** Zertifikat-Management-Overhead, Revocation-Komplexität, schlechtere UX als SSH-basierte Auth ohne echten Sicherheitsgewinn im Homelab.  
**Stattdessen:** SSH-Tunnel + Netbird-VPN für Admin-Zugriff. Caddy `private_admin` Snippet für LAN-only Admin-Vhosts.

## Socket-Aktivierung für SSH {#socket-activation-ssh}

`systemd.sockets.sshd.enable = true` oder `ListenStream=` in `sshd.socket` — SSH über systemd socket activation.  
**Warum nicht:** Wenn die socket-activation-Logik fehlerhaft konfiguriert ist (falscher Port, falsches Protokoll, fehlende Unit-Abhängigkeit), startet SSH nicht mehr — Remote-Zugriff dauerhaft verloren. Der RAM-Gewinn (~5 MB für sshd) rechtfertigt dieses Risiko nicht.  
**Stattdessen:** `services.openssh.enable = true` (permanent aktiv). Für Rescue-Zugang: Dropbear auf Port 2222 als unabhängiger zweiter SSH-Daemon (`my.security.dropbear-rescue.enable`).  
**Quelle:** knowledge-base ADR-012 (Socket Activation Safety).

## mDNS / .local für interne Dienste {#mdns-local}

`avahi.enable = true` + `services.X.mdns = true` oder Hostnamen als `hostname.local` über Caddy/Nginx exponieren.  
**Warum nicht:** mDNS (Multicast DNS, RFC 6762) ist link-local — Multicast-Pakete (224.0.0.251) werden von keinem Router und keinem VPN-Tunnel weitergeleitet. WireGuard/Netbird-Peers bekommen `.local`-Namen nie aufgelöst. Für HTTPS bräuchte man self-signed Zertifikate (CA auf jedem Gerät installieren) oder bleibt bei HTTP — für Dienste die Secrets übertragen inakzeptabel.  
**Stattdessen:** Technitium Split-Horizon DNS: `service.m7c5.de` löst intern zur LAN-IP auf, extern ist der Dienst via Caddy gesperrt. Caddy + Cloudflare DNS-01 Challenge stellt automatisch Let's Encrypt Zertifikate aus. Ergebnis: HTTPS ohne Warnings, funktioniert von LAN und WireGuard/Netbird, kein CA-Management.  
**Ausnahme (acceptable):** Drucker, Chromecasts und andere Consumer-Geräte die kein DNS haben und ausschließlich auf mDNS angewiesen sind — dort ist Avahi für Service-Discovery (nicht für Web-Endpunkte) legitim.

## Siehe auch {#siehe-auch}

- [ADR-2024 — systemd-creds + TPM2](../adr/2024-systemd-creds-tpm.md) — Secrets-Strategie
- [ADR-007 — Dendritische Module](../adr/007-dendritic-one-file-per-service.md) — warum keine Monolith-Stacks oder Auto-Imports
- [ADR-1004 — Unix-Socket-Upstreams](../adr/1004-unix-socket-upstreams.md) — warum kein Socat-Umweg
- [ADR-2008 — nftables L4-Härtung](../adr/2008-nftables-l4-hardening.md) — warum kein legacy iptables
- [ADR-012 — Moderne CLI-Tools](../adr/012-modern-cli-tools.md) — Tooling-Entscheidungen und DX-Standards
- [GUIDE-dendritic-architecture.md](GUIDE-dendritic-architecture.md) — die richtige Architektur statt Antipatterns
