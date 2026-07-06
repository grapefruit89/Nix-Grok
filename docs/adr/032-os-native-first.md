---
meta:
  role: doc
  purpose: ADR-032 OS-native-first für kritische Infrastruktur — lego statt Caddy-ACME als Leitbeispiel
  status: accepted
  date: 2026-07-06
  betrifft:
    - modules/20-security/23-acme.nix
    - modules/10-network/11-network.nix
    - packages/secrets-portal/
  docs:
    - docs/adr/README.md
    - docs/adr/1001-dns-dot-fail-closed.md
    - docs/adr/2024-systemd-creds-tpm.md
    - docs/adr/028-systemd-service-isolation.md
  tags:
    - adr
    - philosophy
    - acme
    - tls
    - security
    - principle
---

# ADR-032: OS-native-first für kritische Infrastruktur {#adr-032}

| Feld | Wert |
|------|------|
| **Status** | accepted |
| **Datum** | 2026-07-06 |
| **Host** | q958 |
| **Leitbeispiel** | `security.acme` (lego) statt Caddy-internes ACME |

## Kontext {#kontext}

Für jede Aufgabe die kritische Infrastruktur berührt (TLS-Zertifikate, DNS,
Secrets-Verschlüsselung, Backup) gibt es meistens mehrere Implementierungsoptionen:

- **Plugin/Extension** eines bereits laufenden Diensts (z.B. Caddy-ACME, Caddy-DNS)
- **Eigenständiges spezialisiertes Programm** (z.B. `lego`, `systemd-creds`, `restic`)
- **Kernel-/OS-nativer Mechanismus** (z.B. `systemd-resolved` DoT, `security.acme` via NixOS)

Die Entscheidung welchen Weg wir gehen ist nicht offensichtlich — beide Optionen
„funktionieren". Aber die Konsequenzen divergieren stark.

## Entscheidung {#entscheidung}

**Prinzip: Für kritische Infrastruktur immer den OS-nativsten / am kernel-nächsten Weg wählen.**

Rangfolge bei der Tool-Auswahl:

```
1. Kernel-/Systemd-Mechanismus    (systemd-creds, systemd-resolved DoT)
2. NixOS-Modul (security.*, networking.*)  (security.acme → lego)
3. Eigenständiges spezialisiertes Tool     (restic, ddns-updater)
4. Plugin eines bestehenden Diensts        (Caddy-ACME, Caddy-DNS-Plugin)
5. Selbstgeschriebener Code               (nur wenn 1-4 nicht passen)
```

Je kritischer die Aufgabe, desto höher muss die Rangfolge sein.

## Leitbeispiel: ACME / TLS-Zertifikate {#acme-beispiel}

### Warum nicht Caddy-ACME? {#warum-nicht-caddy-acme}

Caddy hat einen eingebauten ACME-Client und würde Zertifikate selbst ausstellen
und verwalten wenn man `tls { ... }` in der Caddy-Config schreibt.

**Probleme:**

- Caddy-Neustart = ACME-Prozess unterbrochen (kein unabhängiger Renewal-Service)
- Caddy-Replace (z.B. Migration zu nginx) = alle Certs verloren oder müssen migriert werden
- Caddy-State bläht sich auf (interne ACME-Datenbank, nicht deklarativ beschreibbar)
- Zertifikate sind Caddy-intern — andere Dienste (Postfix, MQTT) können sie nicht nutzen
- Kein NixOS-nativer Lifecycle (kein systemd-Timer, kein `security.acme`-Interface)
- Caddy-Plugin für DNS-Challenge = weiterer Binary-Bestandteil der ausfallen kann

### Warum `security.acme` (lego)? {#warum-lego}

```nix
security.acme.certs."m7c5.de" = {
  domain = "*.m7c5.de";
  dnsProvider = "cloudflare";
  environmentFile = "/run/credentials/acme.env";
  group = "caddy";
};
```

- **Separation of Concerns:** Zertifikat-Management ist unabhängig vom Reverse-Proxy
- **Systemd-nativer Lifecycle:** `acme-m7c5.de.timer` (systemd-Timer) für Renewal
- **Shared Cert:** `group = "caddy"` → Caddy liest das Cert, besitzt es nicht
- **Andere Dienste:** Postfix, Mosquitto, jeder Dienst kann denselben Cert-Pfad nutzen
- **Deklarativ:** Cert-Config ist Nix-Code, nicht Caddy-State
- **lego ist auditierbar:** Eigenständiges Go-Binary mit klarem Scope
- **Caddy bleibt schlank:** Kein DNS-Plugin, kein ACME-State, weniger Angriffsfläche

### Implementierung {#implementierung}

```
modules/20-security/23-acme.nix    → security.acme config (lego)
machines/q958/secrets.nix          → CF_DNS_API_TOKEN in /var/lib/secrets/cloudflare_acme_env
modules/10-network/14-ingress.nix  → Caddy liest /var/lib/acme/m7c5.de/{cert,key}.pem
```

## Weitere Anwendungen des Prinzips {#weitere-anwendungen}

| Aufgabe | Verworfen (Plugin) | Gewählt (OS-nativ) |
|---------|-------------------|-------------------|
| TLS-Zertifikate | Caddy-ACME | `security.acme` (lego) |
| DNS-Verschlüsselung | Caddy-DNS-Proxy | `systemd-resolved` DoT + Technitium |
| Secrets-Verschlüsselung | sops-nix, Vault | `systemd-creds` + TPM2 ([ADR-2024](2024-systemd-creds-tpm.md)) |
| Backup | Borg-Plugin, rclone-Plugin | `restic` (spezialisiert, eigenständig) |
| Secrets-Portal | Vaultwarden-Workflow | `modules/20-security/29-secrets-portal.nix` (Go + systemd-creds) |

## Heuristik für neue Entscheidungen {#heuristik}

Wenn du vor der Wahl stehst ein Plugin X eines Diensts Y zu nutzen
oder ein eigenständiges Tool Z:

1. **Kann der Kernel/systemd das direkt?** → nimm das.
2. **Hat NixOS ein `security.*` oder `networking.*` Modul dafür?** → nimm das.
3. **Gibt es ein eigenständiges, spezialisiertes Tool mit nixpkgs-Paket?** → nimm das.
4. **Plugin von Y:** Nur wenn Y ohnehin der natürliche Owner ist UND die Aufgabe
   nicht kritisch ist (d.h. Y-Ausfall = kein Datenverlust, kein Sicherheitsproblem).
5. **Selbstschreiben:** Nur als „Surgical Glue" für Setup-Logik, nie für kritische Funktionen.

**Warnsignal:** Wenn ein Plugin eines bestehenden Diensts für eine kritische Aufgabe
genutzt wird (TLS, DNS, Backup, Secrets), immer explizit begründen warum OS-nativ
nicht möglich war.

## Konsequenzen {#konsequenzen}

### Positiv {#positiv}
- Klare Verantwortlichkeiten: jeder Dienst hat genau einen Job
- Zertifikate, DNS, Secrets sind austauschbar ohne Caddy/Nginx/Proxy anzufassen
- Auditierbarkeit: jede kritische Funktion ist in einem eigenständigen Binary
- NixOS-Assertions möglich (Nix-Evaluierung kann Verletzungen erkennen)

### Negativ {#negativ}
- Mehr einzelne Services und Abhängigkeiten (Caddy + lego + Technitium statt nur Caddy)
- Startup-Reihenfolge explizit managen (`after = [ "acme-*.service" ]`)

## Siehe auch {#siehe-auch}

- [ADR-1001 — DNS-over-TLS](1001-dns-dot-fail-closed.md) — Technitium statt Caddy-DNS-Proxy
- [ADR-2024 — systemd-creds + TPM2](2024-systemd-creds-tpm.md) — systemd statt sops-nix/Vault
- [ADR-028 — Systemd Service Isolation](028-systemd-service-isolation.md) — ein Dienst, ein Job
- [ANTIPATTERNS.md](../guides/ANTIPATTERNS.md) — sops-nix, mDNS und andere verworfene Wege
