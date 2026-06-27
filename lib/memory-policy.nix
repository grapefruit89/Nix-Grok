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
{ lib }:
let
  gb = n: "${toString n}G";
  mb = n: "${toString n}M";

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

  # Tier 1 — Datenbank (RAM aus profile.nix hardware.ramGB)
  postgres =
    ramGB:
    mkServiceLimits {
      oomScore = -800;
      forceOom = true;
      memoryMax = gb (lib.max 4 (lib.floor (ramGB * 0.3125)));
      memoryHigh = gb (lib.max 3 (lib.floor (ramGB * 0.25)));
    };

  # Tier 4 — Media (expendable, Transcode-Spitzen)
  jellyfin =
    _:
    mkServiceLimits {
      oomScore = 100;
      memoryMax = "6G";
      memoryHigh = "4G";
    };

  sabnzbd =
    _:
    mkServiceLimits {
      oomScore = 300;
      memoryMax = "2G";
      memoryHigh = "1536M";
    };

  # Tier 1 — Ingress & Identität (OOM teils via critical-systemd.nix)
  caddy =
    _:
    mkServiceLimits {
      memoryMax = "768M";
      memoryHigh = "512M";
    };

  pocketId =
    _:
    mkServiceLimits {
      oomScore = -900;
      forceOom = true;
      memoryMax = "256M";
      memoryHigh = "192M";
    };

  # Tier 3 — Observability
  loki =
    _:
    mkServiceLimits {
      oomScore = 300;
      memoryMax = "1G";
      memoryHigh = "768M";
    };

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

  # Tier 4 — *arr (Sonarr, Radarr, Readarr, Prowlarr via arr-helper.nix)
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

  # Tier 5 — Apps (Slice = gemeinsames 2G-Budget für alle Paperless-Units)
  paperless = {
    slice = {
      MemoryMax = lib.mkDefault "2G";
      MemoryHigh = lib.mkDefault "1536M";
    };
    service = mkServiceLimits {
      oomScore = 250;
    };
    # nixpkgs paperless-Modul legt Units in system-paperless.slice ab
    sliceName = "system-paperless.slice";
  };
}
