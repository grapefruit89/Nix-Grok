# Design: Technitium → Blocky Migration

**Datum:** 2026-07-06  
**Status:** Approved — bereit für Implementierung  
**ADR:** wird nach Switch angelegt  

---

## 1. Architektur-Entscheidung

### Problem
Technitium DNS wird über ein 122-Zeilen-Shell-Script (`technitium-dns-configure.service`) imperativ
konfiguriert. Das Script:
- Ruft Technitium's REST-API auf (Login, Token, POST-Requests)
- Setzt DoT-Forwarder wenn noch nicht gesetzt
- Legt Split-Horizon-Zonen an wenn noch nicht vorhanden
- Hat keinerlei idempotente Garantien — API-State ist unsichtbar im Nix-Eval
- Verletzt das NixOS-Prinzip: Config muss aus `nixos-rebuild switch` vollständig rekonstruierbar sein

### Lösung
**Blocky** als deklarativer Drop-in-Ersatz:
- Gesamte Konfiguration in `services.blocky.settings` (YAML-Wert in Nix)
- Kein Shell-Script, kein API-Call, kein interner State
- Ad-blocking für LAN-Clients (Smartphone, alle DHCP-Clients via Router)
- Blocklisten werden beim Start geladen und periodisch aktualisiert (Blocky-native)
- Persönliche Allowlist: `/home/moritz/blocky-allowlist.txt` (easy access zum Editieren)
- Split-Horizon: `customDNS.mapping` — deklarativ, eine Zeile pro Domain

### DNS-Stack danach
```
LAN-Client (Smartphone, PC via Router-DHCP)
    → Port 53 auf 127.0.0.1 (Blocky)
    → Blocky: ad-blocking, split-horizon, dann DoT-Upstreams

Host (q958 selbst)
    → systemd-resolved → DoT direkt (8 Server, strict, kein Blocky-Umweg)
    → Bleibt UNVERÄNDERT — Chicken-Egg-Problem wird vermieden
```

### Invarianten (bleiben erhalten)
- Host-DNS läuft via `resolved → DoT` — unabhängig von Blocky
- Assertions in `1090-host-network.nix` (resolved.dnsovertls = "yes", kein 127.0.0.1 als resolved-DNS)
- Port 53 bleibt auf `127.0.0.1` (kein öffentlicher DNS)
- `90-policy.nix` Assertion: Firewall → Blocky.enable (Technitium-Zweig entfällt)

---

## 2. Blocky-Konfiguration

Modul: `modules/10-network/1002-blocky.nix`

```nix
services.blocky.settings = {
  # ── Port ──────────────────────────────────────────────────────────────────
  ports = {
    dns = 53;
    http = config.my.ports.blocky;  # 1002 (ehemals Technitium)
  };

  # ── DoT-Upstreams (SSoT: config.my.configs.network.dnsBootstrap) ─────────
  # map auf tcp-tls:IP:853 Format für Blocky
  upstreams.groups.default = map
    (s: "tcp-tls:${s.ip}:853")
    config.my.configs.network.dnsBootstrap;

  # ── Bootstrap (zum Auflösen der DoT-Hostnamen ohne DNS) ──────────────────
  bootstrapDns = {
    upstream = "udp:1.1.1.1";
    ips = [ "1.1.1.1" "9.9.9.9" ];
  };

  # ── Split-Horizon ─────────────────────────────────────────────────────────
  # *.domain → LAN-IP (SSoT: config.my.configs.identity.domain + server.lanIP)
  customDNS = {
    mapping = {
      "${config.my.configs.identity.domain}" = config.my.configs.server.lanIP;
    };
    filterUnmappedTypes = false;
  };

  # ── Ad-Blocking ───────────────────────────────────────────────────────────
  blocking = {
    blackLists = {
      ads = [
        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
        "https://dbl.oisd.nl/"
      ];
    };
    whiteLists = {
      ads = [ "/home/moritz/blocky-allowlist.txt" ];
    };
    clientGroupsBlock = {
      default = [ "ads" ];
    };
    refreshPeriod = "24h";
    downloadAttempts = 3;
    downloadCooldown = "2s";
    failOnDnsError = false;
  };

  # ── Logging ───────────────────────────────────────────────────────────────
  log = {
    level = "info";
    format = "text";
  };

  # ── Prometheus-Metriken ───────────────────────────────────────────────────
  prometheus = {
    enable = true;
    path = "/metrics";
  };
};
```

### Allowlist-Datei
- Pfad: `/home/moritz/blocky-allowlist.txt`
- Blocky-Service erhält Leserecht via `ReadOnlyPaths` im systemd-Service
- Initialer Inhalt: wird beim ersten `switch` als leere Datei erstellt falls nicht vorhanden
- Format: eine Domain pro Zeile, `#` für Kommentare

### Split-Horizon-Wildcard
Technitium hatte eine `*.domain`-Zone. Blocky's `customDNS.mapping` mit key `"domain"` matched
auch Subdomains (`*.domain`) wenn `filterUnmappedTypes = false`. Funktional identisch.

---

## 3. Cleanup-Scope (18 Dateien)

### Neu
| Datei | Aktion |
|---|---|
| `modules/10-network/1002-blocky.nix` | **NEU** — Blocky-Modul (Slot frei seit vpn-confinement-Löschung) |

### Stark geändert
| Datei | Was weg? |
|---|---|
| `modules/10-network/1090-host-network.nix` | ~170 Zeilen Technitium-Block inkl. 122-Zeilen-API-Script |

### Umbenennungen / Kleinänderungen
| Datei | Was ändert sich? |
|---|---|
| `modules/00-core/08-ports.nix` | `technitium-dns → blocky` (Wert bleibt 1002) |
| `modules/00-core/06-boot-watchdog.nix` | `requireTechnitium → requireBlocky`, Option + Script-Zeile |
| `modules/10-network/default.nix` | `./1002-blocky.nix` hinzufügen |
| `modules/30-storage/33-backup.nix` | 3 Stellen: Technitium-Path + Stop/Start → Blocky |
| `modules/60-apps/default.nix` | 2 Stellen: Caddy `after`/`wants`: Technitium → Blocky |
| `modules/90-policy/90-policy.nix` | Assertion: nur noch `blocky.enable` (Technitium-Zweig weg) |
| `lib/services-spec.nix` | `technitium-dns-server → blocky` Entry |
| `lib/server-map.nix` | `technitium-dns → blocky` Entry |
| `lib/dns-map.nix` | `technitium-dns-server → blocky` Entry |
| `lib/gatus-endpoints.nix` | `technitium-dns → blocky-dns` Health-Check |
| `lib/service-enable.nix` | `technitium-dns-server → blocky` |
| `machines/q958/rollout.nix` | `technitium-dns-server.enable → blocky.enable` (erstAb 2) |
| `machines/q958/network.nix` | `splitHorizon.enable`-Flag weg, Kommentar aktualisiert |
| `machines/q958/access.nix` | Assertion: `technitium-dns-server.enable → blocky.enable` |

### Impermanence
Technitium hatte `/var/lib/technitium-dns-server` in `extraPaths`. **Blocky ist stateless** —
kein persistenter State nötig, kein Impermanence-Eintrag.

---

## 4. Port-Strategie

**Port 1002** wird von `technitium-dns` zu `blocky` umgetauft.

| Port | Alt | Neu |
|---|---|---|
| 1002 | Technitium WebUI | Blocky HTTP-API + Prometheus-Metriken |
| 53 | Technitium DNS | Blocky DNS (unverändert) |

Keine neuen Ports, kein Konflikt.

---

## 5. Was NICHT ändert sich

- `systemd-resolved` mit DoT (strict) — bleibt komplett unverändert in `1090-host-network.nix`
- Alle Assertions in `1090-host-network.nix` über resolved/DoT — bleiben erhalten
- Port-53-Firewall-Regel (nur 127.0.0.1) — bleibt
- `lib/dns-policy.nix` — bleibt (Host-DNS-Policy betrifft resolved, nicht Blocky)

---

## 6. Risiken

| Risiko | Mitigation |
|---|---|
| Blocky lädt Blocklisten beim ersten Start nicht (externe Abhängigkeit) | `failOnDnsError = false` → degraded mode, DNS läuft trotzdem |
| Split-Horizon-Wildcard verhält sich anders als Technitium | Nach Switch: `nslookup *.domain 127.0.0.1` testen |
| Allowlist-Leserecht für Blocky-Service | `ReadOnlyPaths = ["/home/moritz/blocky-allowlist.txt"]` im systemd-Service |
| `networking.extraHosts` wegfällt (war Technitium-Fallback) | Blocky's `customDNS` macht es überflüssig — Host löst via resolved, nicht Blocky |
