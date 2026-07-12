# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: diskoManaged-Switch — Grenzen was disko ersetzt vs. was bleibt
#   docs:
#     - docs/adr/3024-disko-tier-a-provisioning.md
#     - docs/guides/GUIDE-disko-learning.md
#     - machines/q958/disko-deprecations.json
#   tags:
#     - disko
#     - switch
# ---
{
  lib,
  ...
}:
let
  p = import ./profile.nix;
  tierA = p.storage.tierA;
  diskoManaged = tierA.diskoManaged or false;
in
{
  # ── Switch-Übersicht (eval-Zeit, kein Laufzeit-Eingriff) ─────────────────────
  #
  # diskoManaged = false (LAUFENDES q958):
  #   • hardware.nix: fileSystems /boot + / by-label
  #   • storage.nix: relabelTierALabels (BOOT→NIXBOOT Migration)
  #   • disko-enabled.nix: importiert NICHTS von disko
  #   • disko.nix: nur DR-Doku + diskoConfigurations.q958 (plan/install von USB)
  #
  # diskoManaged = true (NACH Reinstall):
  #   • disko-enabled.nix: disko-Modul + diskoConfigurations.q958 → fileSystems
  #   • hardware.nix: fileSystems AUS (mkIf !diskoManaged)
  #   • storage.nix: relabelTierALabels AUS
  #   • Nach verify: disko-prune-deprecated.sh entfernt DEPRECATED-DISKO-Marker
  #
  # disko ERSETZT: Partitionierung, Formatierung, initiale Labels, Install-Mounts
  # disko ERSETZT NICHT: Tier-B/C-Hotplug, MergerFS, Storage-Mover, Restic-Policy
  #   → bleiben in storage.nix / modules/30-storage / rollout (später polish)

  assertions = [
    {
      assertion = !(diskoManaged && tierA.device == "");
      message = "diskoManaged=true erfordert storage.tierA.device bzw. deviceById in profile.nix";
    }
  ];

  # Eval-Hinweis für nixos-docs / Agenten (erscheint in dry-build logs)
  warnings = lib.optionals (!diskoManaged) [
    "q958 Tier-A: Legacy-Pfad aktiv (diskoManaged=false). disko-Modul im switch inaktiv."
  ];
}
