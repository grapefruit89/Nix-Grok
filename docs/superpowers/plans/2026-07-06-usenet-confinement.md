# Usenet-Confinement Modernisierung — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** POSIX-NetNS-Infrastruktur restlos entfernen und durch modernes host-basiertes UID-Sandbox-Modul ersetzen — atomic in einem Commit + einem `nixos-rebuild switch`.

**Architecture:** Neues Modul `57-usenet-confinement/default.nix` kapselt VPN-Killswitch (BindsTo), DNS-Isolation (BindReadOnlyPaths) und zusätzliches systemd-Hardening für SABnzbd + Prowlarr. Drei Verteidigungsschichten: systemd BPF → nftables skuid → UID-Routing (bereits aktiv in 16-vpn.nix).

**Tech Stack:** NixOS 26.05, systemd, nftables, WireGuard (privado interface)

## Global Constraints

- Alle Änderungen im Repo: `/etc/nixos/` (root-owned, Befehle mit `sudo`)
- Dry-build VOR jedem Switch: `sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh`
- Switch nur in tmux: `tmux new-session 'sudo bash /etc/nixos/scripts/nixos-switch.sh 2>&1 | tee /tmp/switch.log; read'`
- UID prowlarr=5006, UID sabnzbd=5007 (aus `lib/uid-registry.nix`)
- WireGuard interface: `privado`
- VPN-DNS: 198.18.0.1, 198.18.0.2 (aus `machines/q958/profile.nix` → `p.network.privado.dns`)
- Kein imperatives Shell-Skript, nur deklaratives Nix
- Nach jeder Task: `sudo git -C /etc/nixos diff` prüfen bevor commit

---

## File Map

| Aktion | Datei |
|--------|-------|
| **Erstellen** | `modules/50-media/57-usenet-confinement/default.nix` |
| **Löschen** | `modules/10-network/12-vpn-confinement.nix` |
| **Löschen** | `lib/vpn-killswitch.nix` |
| **Löschen** | `lib/vpn-connection.nix` |
| **Ändern** | `modules/10-network/default.nix` |
| **Ändern** | `modules/50-media/default.nix` |
| **Ändern** | `modules/50-media/arr-helper.nix` |
| **Ändern** | `modules/50-media/52-arr.nix` |
| **Ändern** | `modules/50-media/53-sabnzbd.nix` |
| **Ändern** | `lib/nftables-rules.nix` |
| **Ändern** | `machines/q958/default.nix` |
| **Ändern** | `machines/q958/rollout.nix` |

---

## Task 1: Neues Modul erstellen

**Files:**
- Create: `modules/50-media/57-usenet-confinement/default.nix`

**Interfaces:**
- Produces: `options.my.services.usenet-confinement.enable` (mkEnableOption)
- Produces: `config` block der `systemd.services.{sabnzbd,prowlarr}` und `environment.etc."usenet-resolv.conf"` setzt

- [ ] **Schritt 1: Verzeichnis anlegen**

```bash
sudo mkdir -p /etc/nixos/modules/50-media/57-usenet-confinement
```

- [ ] **Schritt 2: Modul schreiben**

Datei `/etc/nixos/modules/50-media/57-usenet-confinement/default.nix` anlegen mit exakt diesem Inhalt:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Usenet VPN-Sandbox — SABnzbd + Prowlarr via Privado WireGuard (host-basiert)
#   docs:
#     - docs/adr/5031-usenet-vpn-sandbox.md
#   services:
#     - sabnzbd
#     - prowlarr
#   tags:
#     - media
#     - usenet
#     - vpn
#     - security
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.services.usenet-confinement;
  privado = config.my.services.privado-vpn;

  sandboxAttrs = {
    bindsTo = [ "sys-subsystem-net-devices-privado.device" ];
    after = [ "sys-subsystem-net-devices-privado.device" ];
    serviceConfig = {
      RestrictNetworkInterfaces = [
        "lo"
        "privado"
      ];
      BindReadOnlyPaths = [ "/etc/usenet-resolv.conf:/etc/resolv.conf" ];
      PrivateIPC = true;
      RestrictNamespaces = true;
      ProcSubset = "pid";
      InaccessiblePaths = [ "/sys/class/net" ];
    };
  };
in
{
  options.my.services.usenet-confinement.enable = lib.mkEnableOption "Usenet VPN-Sandbox (SABnzbd + Prowlarr via Privado WireGuard)";

  config = lib.mkIf cfg.enable {
    environment.etc."usenet-resolv.conf".text = lib.concatMapStrings (dns: "nameserver ${dns}\n") privado.dns;

    systemd.services.sabnzbd = sandboxAttrs;
    systemd.services.prowlarr = sandboxAttrs;
  };
}
```

- [ ] **Schritt 3: Datei prüfen**

```bash
cat /etc/nixos/modules/50-media/57-usenet-confinement/default.nix
```

Erwartet: vollständiger Modulinhalt wie oben.

- [ ] **Schritt 4: Commit**

```bash
sudo git -C /etc/nixos add modules/50-media/57-usenet-confinement/
sudo git -C /etc/nixos commit -m "feat(usenet): add 57-usenet-confinement module (sandbox + DNS isolation)"
```

---

## Task 2: Neues Modul einbinden + Rollout

**Files:**
- Modify: `modules/50-media/default.nix`
- Modify: `machines/q958/rollout.nix`

**Interfaces:**
- Consumes: `options.my.services.usenet-confinement.enable` aus Task 1

- [ ] **Schritt 1: Import in 50-media/default.nix hinzufügen**

Datei `/etc/nixos/modules/50-media/default.nix` — `imports`-Block erweitern:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Media-Domain — Submodule-Aggregation und Enable-Optionen
#   tags:
#     - media
#     - imports
# ---
{ lib, ... }:
{
  imports = [
    ./51-jellyfin.nix
    ./52-arr.nix
    ./53-sabnzbd.nix
    ./54-audiobookshelf.nix
    ./55-navidrome.nix
    ./56-arr-sync
    ./57-usenet-confinement
  ];

  # Centralized options declaration for domain 50
  options.my.services = {
    jellyfin.enable = lib.mkEnableOption "Jellyfin Media Server with Intel QuickSync";
    jellyseerr.enable = lib.mkEnableOption "Jellyseerr Request Manager";
    sonarr.enable = lib.mkEnableOption "Sonarr Series Manager";
    radarr.enable = lib.mkEnableOption "Radarr Movies Manager";
    readarr.enable = lib.mkEnableOption "Readarr Books Manager";
    prowlarr.enable = lib.mkEnableOption "Prowlarr Indexer Proxy";
    sabnzbd.enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
    audiobookshelf = {
      enable = lib.mkEnableOption "Audiobookshelf — Hörbücher & Podcasts";
      enableQuickSync = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Intel VA-API für ffmpeg-Transcode (iGPU UHD 630).";
      };
    };
    navidrome.enable = lib.mkEnableOption "Navidrome Music Server mit Pocket-ID OIDC";
    lidarr.enable = lib.mkEnableOption "Lidarr Music Download Manager";
  };
}
```

- [ ] **Schritt 2: Enable-Flag in rollout.nix hinzufügen**

In `/etc/nixos/machines/q958/rollout.nix` die Zeile für `privado-vpn.enable` suchen:

```nix
    privado-vpn.enable = erstAb 6; # Usenet: SABnzbd + Prowlarr — Key in profile.local.nix
```

Direkt danach einfügen:

```nix
    usenet-confinement.enable = erstAb 6; # VPN-Sandbox: SABnzbd + Prowlarr — BindsTo privado, DNS-Isolation
```

- [ ] **Schritt 3: Dry-build**

```bash
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
```

Erwartet: Build erfolgreich (kein Fehler). Das neue Modul ist aktiv, die alten Libs sind noch vorhanden — eval passt.

- [ ] **Schritt 4: Commit**

```bash
sudo git -C /etc/nixos add modules/50-media/default.nix machines/q958/rollout.nix
sudo git -C /etc/nixos commit -m "feat(usenet): wire 57-usenet-confinement into 50-media + rollout"
```

---

## Task 3: arr-helper.nix bereinigen

**Files:**
- Modify: `modules/50-media/arr-helper.nix`
- Modify: `modules/50-media/52-arr.nix`

**Interfaces:**
- Consumes: nichts mehr aus `lib/vpn-killswitch.nix` oder `lib/vpn-connection.nix`

- [ ] **Schritt 1: arr-helper.nix ersetzen**

Datei `/etc/nixos/modules/50-media/arr-helper.nix` vollständig ersetzen:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Fabrik für *arr-Apps — User, systemd, Caddy, RAM-Limits
#   docs:
#     - docs/adr/007-dendritic-one-file-per-service.md
#     - docs/adr/003-oom-cgroup-isolation.md
#     - docs/adr/011-unified-port-uid-schema.md
#     - docs/guides/GUIDE-media-stack.md
#     - docs/memory_oom.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - sonarr
#     - radarr
#     - readarr
#     - prowlarr
#     - lidarr
#   tags:
#     - media
#     - arr
# ---
{
  config,
  lib,
  ...
}:
let
  factory = import ../../lib/service-factory.nix { inherit lib; };
  memory = import ../../lib/memory-policy.nix {
    inherit lib;
    ramGB = config.my.configs.hardware.ramGB;
  };
in
{
  mkArrService =
    {
      name,
      port,
      dataDir,
      uid,
      gid,
      metadataDir ? null,
      upstreamHost ? "127.0.0.1",
      extraEnv ? { },
    }:
    let
      nameUpper = lib.strings.toUpper name;
    in
    lib.mkMerge [
      {
        services.${name} = {
          enable = true;
          openFirewall = false;
          inherit dataDir;
          settings.server.port = port;
        };

        users.groups.${name} = {
          gid = lib.mkDefault gid;
        };
        users.users.${name} = {
          uid = lib.mkDefault uid;
          group = name;
          isSystemUser = true;
          extraGroups = [ "media" ];
        };
      }

      {
        systemd.services.${name}.environment = {
          "${nameUpper}__AUTH__METHOD" = lib.mkForce "External";
          "${nameUpper}__LOG__LEVEL" = lib.mkDefault "info";
        }
        // extraEnv;
      }

      (factory.mkService {
        inherit config;
        inherit name port upstreamHost;
        mode = "sso";
        hardeningProfile = "dotnet";
        persistDirs = [ dataDir ];
        readWritePaths = [
          dataDir
          "/data/downloads"
          "/data/media"
        ];
        readOnlyPaths = [ ];
        memoryPolicy = memory.arr { };
        extraSystemd = {
          UMask = lib.mkForce "0002";
          EnvironmentFile = [ "/var/lib/secrets/${name}.env" ];
          BindPaths = lib.mkIf (metadataDir != null) [
            "${metadataDir}:/var/lib/${name}/MediaCover"
          ];
        };
      })

      (lib.mkIf (metadataDir != null) {
        systemd.tmpfiles.rules = [
          "d ${metadataDir} 0775 ${name} media -"
          "d /var/lib/${name}/MediaCover 0755 ${name} ${name} -"
        ];
      })
    ];
}
```

- [ ] **Schritt 2: 52-arr.nix bereinigen**

Datei `/etc/nixos/modules/50-media/52-arr.nix` vollständig ersetzen:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Sonarr + Radarr + Readarr + Prowlarr + Lidarr — eine Datei, eine Fabrik (arr-helper.mkArrService)
#   docs:
#     - docs/adr/007-dendritic-one-file-per-service.md
#   services:
#     - sonarr
#     - radarr
#     - readarr
#     - prowlarr
#     - lidarr
#   tags:
#     - media
#     - arr
#     - dendritic
#     - factory
# ---
{
  config,
  lib,
  ...
}:
let
  ports = config.my.ports;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;
  arrHelper = import ./arr-helper.nix { inherit config lib; };

  arrApps = {
    sonarr = {
      port = ports.sonarr;
      uid = uids.sonarr;
      gid = gids.sonarr;
      metadataDir = "/mnt/fast_pool/metadata/sonarr";
      extraEnv = {
        SONARR__UPDATE__BRANCH = "main";
      };
    };
    radarr = {
      port = ports.radarr;
      uid = uids.radarr;
      gid = gids.radarr;
      metadataDir = "/mnt/fast_pool/metadata/radarr";
      extraEnv = {
        RADARR__UPDATE__BRANCH = "master";
      };
    };
    readarr = {
      port = ports.readarr;
      uid = uids.readarr;
      gid = gids.readarr;
      metadataDir = "/mnt/fast_pool/metadata/readarr";
      extraEnv = {
        READARR__UPDATE__BRANCH = "develop";
      };
    };
    prowlarr = {
      port = ports.prowlarr;
      uid = uids.prowlarr;
      gid = gids.prowlarr;
      metadataDir = "/mnt/fast_pool/metadata/prowlarr";
      extraEnv = {
        PROWLARR__UPDATE__BRANCH = "master";
      };
    };
    lidarr = {
      port = ports.lidarr;
      uid = uids.lidarr;
      gid = gids.lidarr;
      metadataDir = "/mnt/fast_pool/metadata/lidarr";
      extraEnv = {
        LIDARR__UPDATE__BRANCH = "master";
      };
    };
  };

  mkArr =
    name: app:
    let
      dataDir = "/var/lib/${name}";
    in
    lib.mkIf config.my.services.${name}.enable (
      arrHelper.mkArrService ({ inherit name dataDir; } // app)
    );
in
{
  config = lib.mkMerge (lib.mapAttrsToList mkArr arrApps);
}
```

- [ ] **Schritt 3: Dry-build**

```bash
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
```

Erwartet: Build erfolgreich. `vpn-killswitch.nix` und `vpn-connection.nix` existieren noch aber werden nicht mehr importiert — kein Problem.

- [ ] **Schritt 4: Commit**

```bash
sudo git -C /etc/nixos add modules/50-media/arr-helper.nix modules/50-media/52-arr.nix
sudo git -C /etc/nixos commit -m "refactor(arr): remove vpn-killswitch + vpn-connection dependencies from arr stack"
```

---

## Task 4: sabnzbd.nix bereinigen

**Files:**
- Modify: `modules/50-media/53-sabnzbd.nix`

- [ ] **Schritt 1: 53-sabnzbd.nix ersetzen**

Datei `/etc/nixos/modules/50-media/53-sabnzbd.nix` vollständig ersetzen:

```nix
# ---
# meta:
#   layer: 3
#   role: module
#   purpose: SABnzbd Usenet — VPN-Sandbox via 57-usenet-confinement
#   docs:
#     - docs/memory_oom.md
#     - docs/adr/5031-usenet-vpn-sandbox.md
#   lib:
#     - lib/memory-policy.nix
#   services:
#     - sabnzbd
#   tags:
#     - media
#     - usenet
# ---
{
  config,
  lib,
  ...
}:
let
  memory = import ../../lib/memory-policy.nix {
    inherit lib;
    ramGB = config.my.configs.hardware.ramGB;
  };
  cfgSabnzbd = config.my.services.sabnzbd;
  portSabnzbd = config.my.ports.sabnzbd;
  uids = config.my.users.registry;
  gids = config.my.groups.registry;
in
{
  config = lib.mkIf cfgSabnzbd.enable {
    my.impermanence.extraPaths = [ "/var/lib/sabnzbd" ];

    services.sabnzbd = {
      enable = true;
      openFirewall = false;
      configFile = null;
      allowConfigWrite = true;
      settings = {
        misc = {
          port = portSabnzbd;
          host = "127.0.0.1";
          language = config.my.configs.locale.language;
        };
      };
    };

    users = {
      groups = {
        media = { };
        sabnzbd.gid = lib.mkDefault gids.sabnzbd;
      };
      users.sabnzbd = {
        uid = lib.mkDefault uids.sabnzbd;
        extraGroups = [ "media" ];
      };
    };

    systemd.services.sabnzbd.serviceConfig = lib.mkMerge [
      (memory.sabnzbd { })
      {
        ProtectSystem = lib.mkForce "strict";
        ProtectHome = lib.mkForce true;
        PrivateTmp = lib.mkForce true;
        PrivateDevices = lib.mkForce true;
        NoNewPrivileges = lib.mkForce true;
        UMask = "0002";
        RuntimeDirectory = "sabnzbd-tmp";
        RuntimeDirectoryMode = "0700";
        ReadWritePaths = [
          "/var/lib/sabnzbd"
          "/data/downloads"
          "/run/sabnzbd-tmp"
        ];
      }
    ];

    systemd.services.sabnzbd.environment = {
      SABNZBD__MISC__TEMP_DIR = "/run/sabnzbd-tmp";
    };
  };
}
```

- [ ] **Schritt 2: Dry-build**

```bash
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
```

Erwartet: Build erfolgreich.

- [ ] **Schritt 3: Commit**

```bash
sudo git -C /etc/nixos add modules/50-media/53-sabnzbd.nix
sudo git -C /etc/nixos commit -m "refactor(sabnzbd): remove vpn-connection/killswitch, VPN-Sandbox via usenet-confinement"
```

---

## Task 5: nftables-rules.nix bereinigen

**Files:**
- Modify: `lib/nftables-rules.nix`

- [ ] **Schritt 1: skuidUsenetGuard vereinfachen**

In `/etc/nixos/lib/nftables-rules.nix` den `skuidUsenetGuard`-Block suchen (aktuell ~Zeilen 57-63) und ersetzen:

```nix
  # Alt (entfernen):
  skuidUsenetGuard =
    if cfg.skuidSegmentation.enable then
      ''
        meta skuid { ${toString uids.prowlarr}, ${toString uids.sabnzbd} } oifname != "lo" oifname != "wt0" oifname != "privado" oifname != "veth-usenet" oifname != "veth-usenet-br" oifname != "usenet-br" ip daddr != { ${lanCidrList}, 192.168.15.0/24 } drop comment "usenet UIDs egress"
      ''
    else "";
```

```nix
  # Neu (einsetzen):
  skuidUsenetGuard =
    if cfg.skuidSegmentation.enable then
      ''
        meta skuid { ${toString uids.prowlarr}, ${toString uids.sabnzbd} } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress"
      ''
    else "";
```

- [ ] **Schritt 2: vpnBridgeAccepts entfernen**

In `/etc/nixos/lib/nftables-rules.nix` den `vpnBridgeAccepts`-Block suchen (~Zeilen 101-105) und komplett entfernen:

```nix
  # Diesen Block entfernen:
  vpnBridgeAccepts = lib.optionalString config.my.services.vpn-confinement.enable (
    lib.concatMapStrings (name: ''
      iifname "${name}-br" accept comment "VPN namespace bridge → host"
    '') (lib.attrNames config.my.services.vpn-confinement.namespaces)
  );
```

Außerdem in der `chain in_trusted` die Zeile `${vpnBridgeAccepts}` entfernen (~Zeile 189).

- [ ] **Schritt 3: Dry-build**

```bash
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
```

Erwartet: Build erfolgreich. nftables-Evaluation sauber.

- [ ] **Schritt 4: nftables-Regel inhaltlich prüfen**

```bash
sudo nix eval --impure --expr 'let pkgs = import <nixpkgs> {}; in "ok"' 2>/dev/null && echo "eval ok"
# Alternativ: nach dem switch in Task 7
nft list ruleset | grep -E "usenet|veth|5006|5007"
```

Erwartet nach Switch: `meta skuid { 5006, 5007 } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress"` — kein `veth-usenet`, kein `192.168.15.0`.

- [ ] **Schritt 5: Commit**

```bash
sudo git -C /etc/nixos add lib/nftables-rules.nix
sudo git -C /etc/nixos commit -m "refactor(nftables): positive whitelist für usenet skuid, remove legacy netns refs"
```

---

## Task 6: Alte Infrastruktur löschen (atomic cleanup)

**Files:**
- Delete: `modules/10-network/12-vpn-confinement.nix`
- Delete: `lib/vpn-killswitch.nix`
- Delete: `lib/vpn-connection.nix`
- Modify: `modules/10-network/default.nix`
- Modify: `machines/q958/default.nix`

> **Hinweis:** Alle Schritte in dieser Task VOR dem dry-build ausführen — erst wenn Imports und Dateien gleichzeitig weg sind ist der Eval sauber.

- [ ] **Schritt 1: Import aus 10-network/default.nix entfernen**

Datei `/etc/nixos/modules/10-network/default.nix` vollständig ersetzen:

```nix
# ---
# id: "network"
# domain: "10"
# status: "active"
# layer: 4
# purpose: "Domäne 10-network — aggregiert Kern-Netzwerk, Gateway, Ingress"
# provides: []
# requires: []
# ports: []
# state_dir: null
# tags: ["network", "imports"]
# ---
{ ... }:
{
  imports = [
    ./11-network.nix
    ./13-gateway.nix
    ./14-ingress.nix
    ./15-databases.nix
    ./16-vpn.nix
    ./17-pocket-id.nix
  ];
}
```

- [ ] **Schritt 2: vpn-confinement Block aus machines/q958/default.nix entfernen**

In `/etc/nixos/machines/q958/default.nix` den gesamten Block entfernen:

```nix
    # Diesen Block entfernen (ca. Zeilen 111-127):
    services.vpn-confinement = {
      namespaces.usenet = {
        wgConf = "/var/lib/secrets/privado.netns.conf";
        address = p.network.privado.address;
        dns = p.network.privado.dns;
        killSwitch = true;
        healthcheck.enable = false;
        accessibleFrom = [
          "192.168.15.0/24"
          "${p.network.lan.ip}/32"
        ];
        services = [
          "sabnzbd"
          "prowlarr"
        ];
      };
    };
```

- [ ] **Schritt 3: Alte Dateien löschen**

```bash
sudo rm /etc/nixos/modules/10-network/12-vpn-confinement.nix
sudo rm /etc/nixos/lib/vpn-killswitch.nix
sudo rm /etc/nixos/lib/vpn-connection.nix
```

- [ ] **Schritt 4: Löschen bestätigen**

```bash
ls /etc/nixos/modules/10-network/
ls /etc/nixos/lib/vpn-*.nix 2>/dev/null || echo "keine vpn-*.nix Dateien mehr"
```

Erwartet: `12-vpn-confinement.nix` nicht mehr vorhanden, kein `vpn-killswitch.nix`, kein `vpn-connection.nix`.

- [ ] **Schritt 5: Keine verbleibenden Referenzen prüfen**

```bash
sudo grep -r "vpn-confinement\|vpn_confinement\|vpnKillSwitch\|vpnConn\|sabInVpn\|useVpnKillSwitch\|veth-usenet\|usenet-br\|vpn-killswitch\|vpn-connection" \
  /etc/nixos/modules /etc/nixos/lib /etc/nixos/machines 2>/dev/null
```

Erwartet: **keine Ausgabe** (keine Matches).

- [ ] **Schritt 6: Dry-build**

```bash
sudo bash /etc/nixos/scripts/nixos-rebuild-safe.sh
```

Erwartet: Build erfolgreich — kein Fehler über fehlende Dateien oder undefinierte Optionen.

- [ ] **Schritt 7: Commit**

```bash
sudo git -C /etc/nixos add -A modules/10-network/ lib/ machines/q958/default.nix
sudo git -C /etc/nixos commit -m "feat(usenet): remove POSIX netns infrastructure (12-vpn-confinement, vpn-killswitch, vpn-connection)"
```

---

## Task 7: Switch + Verifikation

- [ ] **Schritt 1: Switch in tmux**

```bash
tmux new-session 'sudo bash /etc/nixos/scripts/nixos-switch.sh 2>&1 | tee /tmp/switch.log; read'
```

Erwartet: Switch erfolgreich, kein `failed` in der Ausgabe.

- [ ] **Schritt 2: Sandbox-Attribute verifizieren**

```bash
systemctl show sabnzbd -p RestrictNetworkInterfaces,BindsTo,PrivateIPC,ProcSubset
systemctl show prowlarr -p RestrictNetworkInterfaces,BindsTo,PrivateIPC,ProcSubset
```

Erwartet für beide:
```
RestrictNetworkInterfaces=lo privado
BindsTo=sys-subsystem-net-devices-privado.device
PrivateIPC=yes
ProcSubset=pid
```

- [ ] **Schritt 3: DNS-Isolation verifizieren**

```bash
cat /etc/usenet-resolv.conf
```

Erwartet:
```
nameserver 198.18.0.1
nameserver 198.18.0.2
```

- [ ] **Schritt 4: nftables-Regel verifizieren**

```bash
nft list ruleset | grep -E "usenet|5006|5007"
```

Erwartet:
```
meta skuid { 5006, 5007 } oifname != { "lo", "privado" } drop comment "usenet VPN-only egress"
```

Kein Match auf `veth-usenet`, `usenet-br` oder `192.168.15.0`.

- [ ] **Schritt 5: Services laufen**

```bash
systemctl is-active sabnzbd prowlarr
```

Erwartet: `active` für beide.

- [ ] **Schritt 6: Vollständige Legacy-Prüfung**

```bash
sudo grep -r "vpn-confinement\|vpnKillSwitch\|vpnConn\|veth-usenet\|usenet-br\|192\.168\.15\." \
  /etc/nixos/modules /etc/nixos/lib /etc/nixos/machines 2>/dev/null || echo "SAUBER: keine Legacy-Refs"
```

Erwartet: `SAUBER: keine Legacy-Refs`

- [ ] **Schritt 7: Abschlussdokumentation committen**

```bash
sudo git -C /etc/nixos add docs/
sudo git -C /etc/nixos commit -m "docs: ADR-5031 usenet-vpn-sandbox + spec + supersede ADR-2009"
```

---

## Self-Review

**Spec-Coverage:**
- ✅ Löschen 12-vpn-confinement.nix → Task 6
- ✅ Löschen vpn-killswitch.nix → Task 6
- ✅ Löschen vpn-connection.nix → Task 6
- ✅ Neues 57-usenet-confinement Modul → Task 1
- ✅ RestrictNetworkInterfaces → Task 1
- ✅ BindsTo privado.device → Task 1
- ✅ DNS-Isolation (resolv.conf) → Task 1
- ✅ PrivateIPC, RestrictNamespaces, ProcSubset → Task 1
- ✅ nftables positive whitelist → Task 5
- ✅ vpnBridgeAccepts entfernen → Task 5
- ✅ arr-helper.nix bereinigen → Task 3
- ✅ 52-arr.nix bereinigen → Task 3
- ✅ 53-sabnzbd.nix bereinigen → Task 4
- ✅ rollout.nix → Task 2
- ✅ Verifikation → Task 7

**Reihenfolge-Constraint:** Tasks 1-5 können dry-build-geprüft werden. Task 6 (Löschen) und Task 7 (Switch) müssen in einem Zug ohne Unterbrechung durchgeführt werden.
