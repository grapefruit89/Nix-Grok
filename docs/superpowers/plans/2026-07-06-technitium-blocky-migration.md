# Technitium → Blocky Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ersetze Technitium DNS + 122-Zeilen-API-Script vollständig durch Blocky — deklarativ, ad-blocking, stateless.

**Architecture:** Blocky hört auf Port 53 für LAN-Clients und Port 1002 (HTTP-Metriken). Host-DNS bleibt unverändert via `systemd-resolved → DoT` (kein Blocky-Umweg, kein Chicken-Egg-Problem). Split-Horizon wird deklarativ via `customDNS.mapping` gesetzt.

**Tech Stack:** NixOS, `services.blocky.settings` (YAML-Wert), `nixos-rebuild-safe.sh` als Build-Gate

## Global Constraints

- Arbeitsverzeichnis: `/etc/nixos/` (root-owned repo)
- Alle Befehle als `sudo` sofern nicht explizit anders angegeben
- Vor jedem Commit: `sudo scripts/nixos-rebuild-safe.sh` muss exitcode 0 liefern
- Switch nur in tmux: `sudo scripts/nixos-rebuild-safe.sh switch`
- Branch: `master` (single-branch repo, kein Feature-Branch nötig)
- Formatierung: `nixfmt-rfc-style` (läuft automatisch als pre-commit hook)
- Port 1002 = `my.ports.blocky` (ehemals `my.ports.technitium-dns` — gleicher Wert)
- Allowlist-Pfad: `/home/moritz/blocky-allowlist.txt` (unveränderlich, User-Vorgabe)
- SSoT für DoT-Server: `config.my.configs.network.dnsBootstrap` (Liste von `{ip, hostname}`)
- SSoT für Domain: `config.my.configs.identity.domain`
- SSoT für LAN-IP: `config.my.configs.server.lanIP`

---

### Task 1: Port-Registry + Boot-Watchdog umbenennen

**Files:**
- Modify: `modules/00-core/08-ports.nix:22-25`
- Modify: `modules/00-core/06-boot-watchdog.nix:50-53,70`

**Interfaces:**
- Produces: `config.my.ports.blocky` (int, 1002) — wird von Task 2 (Blocky-Modul) und allen lib-Files referenziert

- [ ] **Step 1: Port-Eintrag in 08-ports.nix umbenennen**

Ändere in `modules/00-core/08-ports.nix`:
```nix
# ALT (Zeilen 22-25):
    technitium-dns = lib.mkOption {
      type = lib.types.port;
      default = 1002;
      description = "Technitium DNS Server web UI port (1002).";

# NEU:
    blocky = lib.mkOption {
      type = lib.types.port;
      default = 1002;
      description = "Blocky DNS HTTP API + Prometheus metrics port (1002).";
```

- [ ] **Step 2: boot-watchdog.nix Option umbenennen**

Ändere in `modules/00-core/06-boot-watchdog.nix` alle 3 Stellen:

```nix
# ALT (Zeile 50-53):
    requireTechnitium = lib.mkOption {
      type = lib.types.bool;
      default = config.my.services.technitium-dns-server.enable or false;
    };

# NEU:
    requireBlocky = lib.mkOption {
      type = lib.types.bool;
      default = config.my.services.blocky.enable or false;
    };
```

```nix
# ALT (Zeile 70):
        ${lib.optionalString cfg.requireTechnitium (serviceActive "technitium-dns-server.service")}

# NEU:
        ${lib.optionalString cfg.requireBlocky (serviceActive "blocky.service")}
```

- [ ] **Step 3: Dry-build verifizieren**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

Falls Fehler `attribute 'technitium-dns' missing` → Schritt 1 nochmal prüfen.

- [ ] **Step 4: Commit**

```bash
sudo git -C /etc/nixos add modules/00-core/08-ports.nix modules/00-core/06-boot-watchdog.nix
sudo git -C /etc/nixos commit -m "refactor: rename technitium-dns port → blocky, boot-watchdog requireTechnitium → requireBlocky"
```

---

### Task 2: Blocky-Modul erstellen + importieren

**Files:**
- Create: `modules/10-network/12-blocky.nix`
- Modify: `modules/10-network/default.nix:15-22`

**Interfaces:**
- Consumes: `config.my.ports.blocky` (Task 1), `config.my.configs.network.dnsBootstrap`, `config.my.configs.identity.domain`, `config.my.configs.server.lanIP`
- Produces: `config.my.services.blocky.enable` (bool) — wird von Task 3 (11-network.nix extraHosts), Task 5 (rollout.nix, access.nix), Task 6 (policy) referenziert

- [ ] **Step 1: Allowlist-Datei initial erstellen**

```bash
touch /home/moritz/blocky-allowlist.txt
echo "# Blocky persönliche Allowlist — eine Domain pro Zeile" >> /home/moritz/blocky-allowlist.txt
echo "# Beispiel: doubleclick.net" >> /home/moritz/blocky-allowlist.txt
```

- [ ] **Step 2: 12-blocky.nix erstellen**

Erstelle `/etc/nixos/modules/10-network/12-blocky.nix` mit diesem Inhalt:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Blocky DNS — ad-blocking, split-horizon, DoT-Upstreams für LAN-Clients
#   services:
#     - blocky
#   tags:
#     - dns
#     - ad-blocking
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.blocky;
  dot = config.my.configs.network.dnsBootstrap;
in
{
  options.my.services.blocky = {
    enable = lib.mkEnableOption "Blocky DNS resolver with ad-blocking for LAN clients";
  };

  config = lib.mkIf cfg.enable {
    services.blocky = {
      enable = true;
      settings = {
        ports = {
          dns = 53;
          http = config.my.ports.blocky;
        };

        upstreams.groups.default = map (s: "tcp-tls:${s.ip}:853") dot;

        bootstrapDns = [
          "1.1.1.1"
          "9.9.9.9"
        ];

        customDNS = {
          mapping = {
            "${config.my.configs.identity.domain}" = config.my.configs.server.lanIP;
          };
          filterUnmappedTypes = false;
        };

        blocking = {
          blackLists.ads = [
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
            "https://dbl.oisd.nl/"
          ];
          whiteLists.ads = [ "/home/moritz/blocky-allowlist.txt" ];
          clientGroupsBlock.default = [ "ads" ];
          refreshPeriod = "24h";
          downloadAttempts = 3;
          downloadCooldown = "2s";
          failOnDnsError = false;
        };

        log = {
          level = "info";
          format = "text";
        };

        prometheus = {
          enable = true;
          path = "/metrics";
        };
      };
    };

    # Allowlist liegt in /home/moritz — world-readable (644) via tmpfiles
    systemd.tmpfiles.rules = [
      "f /home/moritz/blocky-allowlist.txt 0644 moritz users -"
    ];

    systemd.services.blocky = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        OOMScoreAdjust = lib.mkDefault (-300);
      };
    };
  };
}
```

- [ ] **Step 3: Import in default.nix einfügen**

Ändere `modules/10-network/default.nix`:
```nix
# ALT:
  imports = [
    ./11-network.nix
    ./13-gateway.nix

# NEU:
  imports = [
    ./11-network.nix
    ./12-blocky.nix
    ./13-gateway.nix
```

- [ ] **Step 4: Dry-build verifizieren**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

Typischer Fehler: `attribute 'blocky' missing in my.services` → Option-Definition in 12-blocky.nix prüfen.

- [ ] **Step 5: Commit**

```bash
sudo git -C /etc/nixos add modules/10-network/12-blocky.nix modules/10-network/default.nix
sudo git -C /etc/nixos commit -m "feat: add Blocky DNS module with ad-blocking and split-horizon"
```

---

### Task 3: 11-network.nix — Technitium-Block entfernen

**Files:**
- Modify: `modules/10-network/11-network.nix` (275 Zeilen → ~130 Zeilen)

**Was weg:**
- `cfgTechnitium` let-Binding (Zeile 11)
- `options.my.services.technitium-dns-server` Block (Zeilen 24-29)
- Gesamter `lib.mkIf cfgTechnitium.enable (...)` Block (Zeilen 46-218)
- Enthält: API-Script, `technitium-dns-configure.service`, `services.technitium-dns-server`, `my.impermanence.extraPaths`

**Was bleibt (aus mkIf herausgezogen):**
- `services.resolved` Config
- `networking.resolvconf.enable`, `networking.nameservers`, `networking.enableIPv6`
- `networking.extraHosts` (jetzt conditional auf `config.my.services.blocky.enable`)
- Alle 6 assertions (Wortlaut "Technitium" → "Blocky" wo nötig)

**Interfaces:**
- Consumes: `config.my.services.blocky.enable` (Task 2)

- [ ] **Step 1: 11-network.nix komplett neu schreiben**

Ersetze den gesamten Inhalt von `/etc/nixos/modules/10-network/11-network.nix` mit:

```nix
# Valkey + PostgreSQL → 15-databases.nix
# Netbird + Privado VPN → 16-vpn.nix
# Pocket-ID → 17-pocket-id.nix
# Blocky DNS → 12-blocky.nix
{
  config,
  lib,
  ...
}:
let
  caddySnippets = import ../../lib/caddy-snippets.nix {
    pocketIdPort =
      if config.my.services.pocket-id.enable or false then config.my.ports.pocket-id else null;
    lanCidr = "192.168.0.0/16";
    oauth2proxyPort = if config.my.services.oauth2-proxy.enable or false then 4180 else null;
    oauth2Domain = config.my.configs.identity.domain;
  };
  dot = config.my.configs.network.dnsBootstrap;
  resolvedDns = lib.concatStringsSep " " (map (s: "${s.ip}#${s.hostname}") dot);
  domain = config.my.configs.identity.domain;
  lanIp = config.my.configs.server.lanIP;
in
{
  config = lib.mkMerge [
    # ── IPv6: gezielt pro Interface aus (Netbird/WG unberührt) ──────────────
    {
      boot.kernel.sysctl = lib.mkMerge (
        map (iface: {
          "net.ipv6.conf.${iface}.disable_ipv6" = lib.mkDefault 1;
          "net.ipv6.conf.${iface}.accept_ra" = lib.mkDefault 0;
          "net.ipv6.conf.${iface}.autoconf" = lib.mkDefault 0;
        }) config.my.configs.network.ipv6.disableOnInterfaces
      );
    }

    # ── HOST-DNS: resolved → DoT (direkt, kein Blocky-Umweg) ─────────────────
    # ADR-1001: Host-DNS hat keine Abhängigkeit von Blocky — kein Chicken-Egg-Problem.
    # DNSOverTLS=yes: strict — niemals Plaintext-Fallback erlaubt.
    {
      services.resolved = {
        enable = lib.mkForce true;
        settings.Resolve = {
          DNS = resolvedDns;
          DNSOverTLS = "yes";
          DNSSEC = "allow-downgrade";
          LLMNR = "no";
          MulticastDNS = "no";
          Cache = "yes";
          FallbackDNS = "";
        };
      };
      networking.resolvconf.enable = lib.mkForce false;
      networking.nameservers = lib.mkForce [ ];
      networking.enableIPv6 = lib.mkDefault false;

      # Split-Horizon für Host via /etc/hosts (NSS vor DNS — Host nutzt resolved, nicht Blocky).
      networking.extraHosts = lib.mkIf config.my.services.blocky.enable (
        let
          fqdns = lib.concatStringsSep " " (
            lib.mapAttrsToList (
              _name: entry: lib.optionalString (entry.subdomain != null) "${entry.subdomain}.${domain}"
            ) config.my.services.spec
          );
        in
        lib.optionalString (fqdns != "") "${lanIp} ${fqdns}"
      );

      assertions = [
        {
          assertion = config.services.resolved.enable or false;
          message = "DNS: systemd-resolved muss aktiv sein (direkt DoT ohne Blocky-Umweg).";
        }
        {
          assertion = (config.services.resolved.settings.Resolve.DNSOverTLS or "no") == "yes";
          message = "DNS-POLICY: DNSOverTLS muss 'yes' (strict) sein — Host-DNS geht direkt an DoT-Upstreams, kein Plaintext-Fallback erlaubt!";
        }
        {
          assertion = (config.services.resolved.settings.Resolve.DNS or "") != "127.0.0.1";
          message = "DNS-POLICY: resolved darf nicht 127.0.0.1 (Blocky) als primary DNS nutzen — direkt DoT verwenden!";
        }
        {
          assertion = config.networking.nameservers == [ ];
          message = "DNS-POLICY: networking.nameservers muss leer sein — externe Einträge würden /etc/resolv.conf überschreiben und DoT umgehen!";
        }
        {
          assertion = config.my.configs.network.ipv6.firewall == false;
          message = "IPv6: Homelab-v4-only — my.configs.network.ipv6.firewall muss false sein.";
        }
        {
          assertion = !(config.networking.enableIPv6 or true);
          message = "IPv6: networking.enableIPv6 muss false sein — Kernel-Ebene muss IPv6 deaktivieren.";
        }
      ];
    }

    # ── CADDY GLOBAL CONFIG & SNIPPETS ────────────────────────────────────────
    # ADR 018: Dual-Log — default-Logger (stdout→journald→CrowdSec) bleibt unverändert.
    # dsgvo_access-Logger abonniert http.log.access (alle vHosts) und schreibt
    # IP-maskierte Logs auf /24 (IPv4) / /48 (IPv6) nach /var/log/caddy/dsgvo.json.
    {
      services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
        servers {
          trusted_proxies static private_ranges
          timeouts {
            read_body   30s
            read_header 10s
            idle        5m
          }
        }

        log dsgvo_access {
          include http.log.access
          output file /var/log/caddy/dsgvo.json {
            roll_size 100mb
            roll_keep 14
            roll_keep_for 720h
          }
          format filter {
            wrap json
            fields {
              request>remote_ip ip_mask {
                ipv4 24
                ipv6 48
              }
              request>client_ip ip_mask {
                ipv4 24
                ipv6 48
              }
            }
          }
          level INFO
        }
      '';

      services.caddy.logFormat = lib.mkIf config.services.caddy.enable (
        lib.mkForce ''
          level INFO
          output stdout
          format json
        ''
      );
      services.caddy.extraConfig = lib.mkIf config.services.caddy.enable (
        lib.mkBefore caddySnippets.extraConfig
      );

      systemd.tmpfiles.rules = lib.mkIf config.services.caddy.enable [
        "d /var/log/caddy 0750 caddy caddy -"
      ];
    }
  ];
}
```

- [ ] **Step 2: Dry-build verifizieren**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

Typischer Fehler: `attribute 'technitium-dns-server' missing` → irgendeine andere Datei referenziert noch das alte Option. Suche mit:
```bash
sudo grep -rn "technitium-dns-server" /etc/nixos/ --include="*.nix" | grep -v ".git"
```

- [ ] **Step 3: Commit**

```bash
sudo git -C /etc/nixos add modules/10-network/11-network.nix
sudo git -C /etc/nixos commit -m "refactor: remove Technitium from 11-network.nix, promote resolved/extraHosts/assertions to unconditional"
```

---

### Task 4: Lib-Dateien umbenennen (5 Dateien)

**Files:**
- Modify: `lib/services-spec.nix` (Technitium-Eintrag → Blocky)
- Modify: `lib/server-map.nix` (ID `technitium-dns` → `blocky`)
- Modify: `lib/dns-map.nix` (`technitium-dns-server` → `blocky`)
- Modify: `lib/gatus-endpoints.nix` (`technitium-dns` → `blocky-dns`)
- Modify: `lib/service-enable.nix` (`technitium-dns-server` → `blocky`)

- [ ] **Step 1: services-spec.nix**

Ändere `lib/services-spec.nix`:
```nix
# ALT:
    technitium-dns-server = {
      port = ports.technitium-dns;
      zone = "admin-hangar";
      subdomain = "dns";
      description = "Technitium DNS Server";
    };

# NEU:
    blocky = {
      port = ports.blocky;
      zone = "admin-hangar";
      subdomain = "dns";
      description = "Blocky DNS (ad-blocking, split-horizon)";
    };
```

- [ ] **Step 2: server-map.nix**

Ändere `lib/server-map.nix`:
```nix
# ALT:
    technitium-dns = {
      id = 1002;
      transport = "tcp:1002";
      module = "10-network";
      sso = false;
    };

# NEU:
    blocky = {
      id = 1002;
      transport = "tcp:1002";
      module = "10-network";
      sso = false;
    };
```

- [ ] **Step 3: dns-map.nix**

Ändere `lib/dns-map.nix`:
```nix
# ALT:
    technitium-dns-server = fqdn "dns";

# NEU:
    blocky = fqdn "dns";
```

- [ ] **Step 4: gatus-endpoints.nix**

Ändere `lib/gatus-endpoints.nix`:
```nix
# ALT:
    (mkDns {
      name = "technitium-dns";
      group = "critical";
      queryName = "cloudflare.com";
    })

# NEU:
    (mkDns {
      name = "blocky-dns";
      group = "critical";
      queryName = "cloudflare.com";
    })
```

- [ ] **Step 5: service-enable.nix**

Ändere `lib/service-enable.nix`:
```nix
# ALT:
        technitium-dns-server = mySvc.technitium-dns-server.enable or false;

# NEU:
        blocky = mySvc.blocky.enable or false;
```

- [ ] **Step 6: Dry-build verifizieren**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

- [ ] **Step 7: Commit**

```bash
sudo git -C /etc/nixos add lib/services-spec.nix lib/server-map.nix lib/dns-map.nix lib/gatus-endpoints.nix lib/service-enable.nix
sudo git -C /etc/nixos commit -m "refactor: rename technitium → blocky across all lib files"
```

---

### Task 5: Machine-Config (machines/q958/)

**Files:**
- Modify: `machines/q958/rollout.nix` (enable-Flag umbenennen)
- Modify: `machines/q958/network.nix` (splitHorizon-Option + Firewall-Condition)
- Modify: `machines/q958/access.nix` (Assertion umbenennen)

- [ ] **Step 1: rollout.nix**

Ändere `machines/q958/rollout.nix`:
```nix
# ALT:
    technitium-dns-server.enable = erstAb 2;

# NEU:
    blocky.enable = erstAb 2;
```

- [ ] **Step 2: network.nix — splitHorizon-Zeile und Firewall-Condition**

Ändere `machines/q958/network.nix`:

Entferne diese Zeile komplett (splitHorizon ist jetzt immer in Blocky aktiviert):
```nix
# ENTFERNEN:
  my.services.technitium-dns-server.splitHorizon.enable = true;
```

Ändere die Firewall-Condition:
```nix
# ALT:
  networking.firewall.interfaces.${lan.interface} =
    lib.mkIf (config.my.services.technitium-dns-server.enable && !config.my.security.firewall.enable)

# NEU:
  networking.firewall.interfaces.${lan.interface} =
    lib.mkIf (config.my.services.blocky.enable && !config.my.security.firewall.enable)
```

Aktualisiere den Kommentar am Anfang der Datei:
```nix
# ALT:
#     - technitium-dns-server

# NEU:
#     - blocky
```

- [ ] **Step 3: access.nix — Assertion**

Ändere `machines/q958/access.nix`:
```nix
# ALT:
    {
      assertion =
        !(config.my.services.technitium-dns-server.enable or false) || lan.dns == [ "127.0.0.1" ];
      message = "ACCESS: Technitium aktiv → LAN-DNS muss 127.0.0.1 sein.";
    }

# NEU:
    {
      assertion =
        !(config.my.services.blocky.enable or false) || lan.dns == [ "127.0.0.1" ];
      message = "ACCESS: Blocky aktiv → LAN-DNS muss 127.0.0.1 sein.";
    }
```

- [ ] **Step 4: Dry-build verifizieren**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

- [ ] **Step 5: Commit**

```bash
sudo git -C /etc/nixos add machines/q958/rollout.nix machines/q958/network.nix machines/q958/access.nix
sudo git -C /etc/nixos commit -m "refactor: update q958 machine config — technitium → blocky"
```

---

### Task 6: Supporting Modules (backup, 60-apps, 90-policy)

**Files:**
- Modify: `modules/30-storage/33-backup.nix` (3 Stellen)
- Modify: `modules/60-apps/default.nix` (2 Stellen)
- Modify: `modules/90-policy/90-policy.nix` (Assertion vereinfachen)

- [ ] **Step 1: 33-backup.nix — Impermanence-Pfad entfernen**

Ändere `modules/30-storage/33-backup.nix`:
```nix
# ALT:
          # ── Netzwerk-Konfiguration (nicht deklarativ in NixOS-Modul) ─────
          "${cfgImp.persistMountPoint}/var/lib/technitium-dns-server"

# NEU (ganze Sektion mit Kommentar entfernen):
# (Diese beiden Zeilen komplett löschen — Blocky ist stateless, kein Persist nötig)
```

- [ ] **Step 2: 33-backup.nix — Stop/Start in backup-Scripts**

Ändere in `backupPrepareCommand`:
```bash
# ALT:
            audiobookshelf technitium-dns-server || true

# NEU:
            audiobookshelf blocky || true
```

Ändere in `backupCleanupCommand`:
```bash
# ALT:
            audiobookshelf technitium-dns-server || true

# NEU:
            audiobookshelf blocky || true
```

- [ ] **Step 3: 60-apps/default.nix — Caddy after/wants**

Ändere `modules/60-apps/default.nix` (beide Stellen):
```nix
# ALT:
      after = lib.mkAfter (
        lib.optional config.my.services.technitium-dns-server.enable "technitium-dns-server.service"

# NEU:
      after = lib.mkAfter (
        lib.optional config.my.services.blocky.enable "blocky.service"
```

```nix
# ALT:
      wants =
        lib.optional config.my.services.technitium-dns-server.enable "technitium-dns-server.service"

# NEU:
      wants =
        lib.optional config.my.services.blocky.enable "blocky.service"
```

- [ ] **Step 4: 90-policy/90-policy.nix — Assertion vereinfachen**

Ändere `modules/90-policy/90-policy.nix`:
```nix
# ALT:
      {
        assertion =
          config.my.security.firewall.enable
          -> (config.my.services.blocky.enable || config.my.services.technitium-dns-server.enable);
        message = "POLICY: Firewall aktiviert, aber kein DNS-Resolver (Blocky/Technitium) — DNS-Leck möglich.";
      }

# NEU:
      {
        assertion = config.my.security.firewall.enable -> config.my.services.blocky.enable;
        message = "POLICY: Firewall aktiviert, aber kein DNS-Resolver (Blocky) — DNS-Leck möglich.";
      }
```

- [ ] **Step 5: Dry-build — finales Gate**

```bash
sudo scripts/nixos-rebuild-safe.sh
```
Expected: `✓ Dry-build erfolgreich`

Falls noch `technitium` Fehler auftauchen:
```bash
sudo grep -rn "technitium" /etc/nixos/ --include="*.nix" | grep -v ".git" | grep -v "docs/"
```
Alle Treffer bereinigen.

- [ ] **Step 6: Commit**

```bash
sudo git -C /etc/nixos add modules/30-storage/33-backup.nix modules/60-apps/default.nix modules/90-policy/90-policy.nix
sudo git -C /etc/nixos commit -m "refactor: update backup, caddy-deps, policy assertion — technitium → blocky"
```

---

### Task 7: Switch + Verify + Push

**Files:** keine Änderungen — nur Verifikation

- [ ] **Step 1: Switch in tmux**

```bash
sudo scripts/nixos-rebuild-safe.sh switch
```
Dies startet tmux und führt `nixos-rebuild switch` darin aus. Warten bis fertig.

- [ ] **Step 2: Blocky-Status prüfen**

```bash
systemctl status blocky
```
Expected: `Active: active (running)`

```bash
journalctl -u blocky -n 30 --no-pager
```
Expected: Startup-Logs ohne `ERROR`. Warnung über fehlende Blocklist-Downloads ist OK (failOnDnsError = false).

- [ ] **Step 3: DNS-Funktionalität testen**

Basis-DNS:
```bash
dig @127.0.0.1 cloudflare.com +short
```
Expected: eine oder mehrere IP-Adressen

Split-Horizon (ersetze `DOMAIN` mit dem tatsächlichen Wert von `config.my.configs.identity.domain`):
```bash
dig @127.0.0.1 caddy.DOMAIN +short
```
Expected: LAN-IP (z.B. 192.168.x.x)

Ad-Blocking:
```bash
dig @127.0.0.1 doubleclick.net +short
```
Expected: leer, NXDOMAIN, oder 0.0.0.0 (geblockt)

- [ ] **Step 4: HTTP-Endpunkt testen**

```bash
curl -s http://localhost:1002/metrics | head -5
```
Expected: Prometheus-Metriken beginnen mit `# HELP blocky_`

```bash
curl -s http://localhost:1002/api/blocking/status
```
Expected: `{"enabled":true}` oder ähnliches JSON

- [ ] **Step 5: Technitium komplett weg prüfen**

```bash
systemctl status technitium-dns-server 2>&1
```
Expected: `Unit technitium-dns-server.service could not be found.`

```bash
sudo grep -rn "technitium" /etc/nixos/ --include="*.nix" | grep -v ".git" | grep -v "docs/"
```
Expected: **keine Treffer** (ausgenommen docs/ wo der alte Name in ADRs historisch stehen darf)

- [ ] **Step 6: Gatus prüfen (falls läuft)**

```bash
curl -s http://localhost:$(nix eval --raw .#nixosConfigurations.q958.config.my.ports.gatus 2>/dev/null || echo "3000")/api/v1/endpoints/statuses | python3 -m json.tool | grep -A3 "blocky"
```
Expected: `blocky-dns` im Status

- [ ] **Step 7: Push**

```bash
sudo git -C /etc/nixos push origin master:main
```
Expected: Push zu GitHub erfolgreich

---

## Schnellreferenz: Alle betroffenen Dateien

| Datei | Aktion | Task |
|---|---|---|
| `modules/00-core/08-ports.nix` | `technitium-dns → blocky` | 1 |
| `modules/00-core/06-boot-watchdog.nix` | `requireTechnitium → requireBlocky` | 1 |
| `modules/10-network/12-blocky.nix` | **NEU** | 2 |
| `modules/10-network/default.nix` | import hinzufügen | 2 |
| `modules/10-network/11-network.nix` | ~170 Zeilen Technitium raus | 3 |
| `lib/services-spec.nix` | Entry umbenennen | 4 |
| `lib/server-map.nix` | Entry umbenennen | 4 |
| `lib/dns-map.nix` | Entry umbenennen | 4 |
| `lib/gatus-endpoints.nix` | Health-Check umbenennen | 4 |
| `lib/service-enable.nix` | Key umbenennen | 4 |
| `machines/q958/rollout.nix` | enable-Flag | 5 |
| `machines/q958/network.nix` | splitHorizon weg, Firewall-Cond | 5 |
| `machines/q958/access.nix` | Assertion | 5 |
| `modules/30-storage/33-backup.nix` | Path + Stop/Start | 6 |
| `modules/60-apps/default.nix` | Caddy after/wants | 6 |
| `modules/90-policy/90-policy.nix` | Assertion vereinfachen | 6 |
