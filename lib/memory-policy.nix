# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: systemd MemoryMax/MemoryHigh und OOMScoreAdjust pro Dienst-Tier
#   docs:
#     - docs/adr/003-oom-cgroup-isolation.md
#     - docs/memory_oom.md
#   tags:
#     - oom
#     - systemd
# ---
#
# Verwendung: import ./memory-policy.nix { inherit lib; ramGB = config.my.configs.hardware.ramGB; }
#
# RAM-adaptive Dienste leiten ihre Limits aus ramGB ab — damit skaliert die Konfiguration
# automatisch mit jeder Maschine (profile.nix → default.nix → Option → hier).
# Feste Limits bleiben wo die Anwendung eine bekannte, maschinenunabhängige Obergrenze hat.
#
# Formel-Konvention (RAM-adaptive):
#   memoryMax  = floor(ramGB * Faktor), mit Mindestgrenze
#   memoryHigh = 75% von memoryMax (Kernel warnt ab hier, OOM-Kill erst ab max)
{
  lib,
  ramGB ? 16,
}:
let
  gb = n: "${toString n}G";
  mb = n: "${toString n}M";

  # Helper: berechnet MemoryHigh aus MemoryMax (75%, mindestens 1 GB)
  high75 = maxGB: lib.max 1 (lib.floor (maxGB * 0.75));

  mkServiceLimits =
    {
      oomScore ? null,
      memoryMax ? null,
      memoryHigh ? null,
      forceOom ? false,
    }:
    let
      oom =
        if oomScore != null then
          if forceOom then lib.mkForce oomScore else lib.mkDefault oomScore
        else
          null;
    in
    lib.filterAttrs (_: v: v != null) {
      OOMScoreAdjust = oom;
      MemoryMax = if memoryMax != null then lib.mkDefault memoryMax else null;
      MemoryHigh = if memoryHigh != null then lib.mkDefault memoryHigh else null;
    };
in
{
  inherit mkServiceLimits gb mb;

  # ── Tier 1 — Datenbank ──────────────────────────────────────────────────────
  # postgres nimmt ramGB als explizites Argument (Caller: memory.postgres ramGB).
  # Parameter-ramGB schattiert das äußere ramGB — Nix wählt immer den innersten Binding.
  # 31.25% = PostgreSQL-Empfehlung für shared_buffers-kompatible MemoryMax auf dedizierten DB-Servern.
  postgres =
    ramGB:
    mkServiceLimits {
      oomScore = -800;
      forceOom = true;
      memoryMax = gb (lib.max 4 (lib.floor (ramGB * 0.3125)));
      memoryHigh = gb (lib.max 3 (lib.floor (ramGB * 0.25)));
    };

  # ── Tier 4 — Media ──────────────────────────────────────────────────────────
  # 20% des RAM für Jellyfin: Transcode-Puffer + Plugin-Overhead skalieren mit RAM.
  # Mindestens 2 GB: unter 2 GB ist Jellyfin praktisch unbrauchbar (keine HW-Transcode-Reserve).
  # Auf q958 (32 GB): max=6 GB, high=4 GB — entspricht bisheriger Konfiguration.
  jellyfin =
    _:
    let
      maxGB = lib.max 2 (lib.floor (ramGB * 0.2));
    in
    mkServiceLimits {
      oomScore = 100;
      memoryMax = gb maxGB;
      memoryHigh = gb (high75 maxGB);
    };

  # 6.25% des RAM für SABnzbd: Download-Puffer + Dekompression skalieren mit RAM.
  # Mindestens 1 GB: unter 1 GB bricht die Pufferlogik bei großen NZBs zusammen.
  # Auf q958 (32 GB): max=2 GB, high=1 GB — entspricht bisheriger Konfiguration.
  sabnzbd =
    _:
    let
      maxGB = lib.max 1 (lib.floor (ramGB * 0.0625));
    in
    mkServiceLimits {
      oomScore = 300;
      memoryMax = gb maxGB;
      memoryHigh = gb (high75 maxGB);
    };

  # ── Tier 1 — Ingress & Identität ────────────────────────────────────────────
  # Caddy: reiner Reverse-Proxy, feste Obergrenze — kein RAM-Scaling sinnvoll.
  caddy =
    _:
    mkServiceLimits {
      memoryMax = "768M";
      memoryHigh = "512M";
    };

  # PocketID: SSO-Dienst, sehr schlanker Footprint — fest auf 256M.
  # OOMScore -900: kritischer Identitätsdienst, letzter Kandidat für OOM-Kill.
  pocketId =
    _:
    mkServiceLimits {
      oomScore = -900;
      forceOom = true;
      memoryMax = "256M";
      memoryHigh = "192M";
    };

  # ── Tier 3 — Observability ──────────────────────────────────────────────────
  # Loki: auf 16-GB-Hosts enger (768M), ab 24 GB wieder RAM-skaliert.
  loki =
    _:
    let
      maxGB = lib.max 1 (lib.floor (ramGB * 0.03));
      maxStr = if ramGB <= 16 then "768M" else gb maxGB;
      highStr = if ramGB <= 16 then "512M" else gb (high75 maxGB);
    in
    mkServiceLimits {
      oomScore = 300;
      memoryMax = maxStr;
      memoryHigh = highStr;
    };

  # Vector/Grafana: feste Limits — Log-Shipper und Dashboard haben bekannte Footprints.
  vector =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  grafana =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  # ── Tier 4 — *arr Stack ─────────────────────────────────────────────────────
  # Sonarr/Radarr/Readarr/Prowlarr: feste 512M — Metadaten-Datenbanken sind klein,
  # kein Scaling sinnvoll (Burst durch RSS-Sync ist kurz, nicht RAM-abhängig).
  arr =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  audiobookshelf =
    _:
    mkServiceLimits {
      oomScore = 150;
      memoryMax = "1G";
      memoryHigh = "768M";
    };

  navidrome =
    _:
    mkServiceLimits {
      oomScore = 200;
      memoryMax = "512M";
      memoryHigh = "384M";
    };

  # ── Tier 5 — Apps ───────────────────────────────────────────────────────────
  # Paperless: 6.25% des RAM für das gesamte Slice (alle Units zusammen).
  # Mindestens 2 GB: OCR + ML-Klassifizierung braucht Arbeitsspeicher.
  # Auf q958 (32 GB): max=2 GB, high=1 GB — entspricht bisheriger Konfiguration.
  # Slice-Budget teilen sich: paperless-webserver, paperless-scheduler, paperless-task-queue.
  paperless =
    let
      maxGB = lib.max 2 (lib.floor (ramGB * 0.0625));
    in
    {
      slice = {
        MemoryMax = lib.mkDefault (gb maxGB);
        MemoryHigh = lib.mkDefault (gb (high75 maxGB));
      };
      service = mkServiceLimits {
        oomScore = 250;
      };
      # nixpkgs paperless-Modul legt Units in system-paperless.slice ab
      sliceName = "system-paperless.slice";
    };
}