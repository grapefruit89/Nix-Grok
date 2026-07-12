# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Swap-Thrashing verhindern — systemd-oomd vor unkontrolliertem ZRAM-Paging
#   docs:
#     - docs/memory_oom.md
#     - docs/adr/003-oom-cgroup-isolation.md
#   tags:
#     - policy
#     - oom
#     - memory
# ---
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.policy.memoryPressure;
in
{
  options.my.policy.memoryPressure = {
    enable = lib.mkEnableOption ''
      Swap-Thrashing verhindern: systemd-oomd beendet RAM-Fresser (system- und
      user-Slices), bevor der Kernel unkontrolliert in ZRAM auslagert.
      Ergänzt cgroup MemoryMax aus lib/memory-policy.nix — kein Ersatz dafür.
    '';
  };

  config = lib.mkIf cfg.enable {
    systemd.oomd = {
      enable = true;
      enableRootSlice = true;
      enableSystemSlice = true;
      enableUserSlices = true;
    };
  };
}
