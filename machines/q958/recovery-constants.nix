# ---
# meta:
#   layer: 2
#   role: machine
#   purpose: Deklarative Recovery-Konstanten — keine Secrets, kein profile.local
#   tags:
#     - recovery
#     - dr
# ---
# Sync mit machines/q958/profile.nix (öffentliche Werte). Kein import profile.nix —
# profile.nix verlangt profile.local.nix; Recovery-ISO muss ohne Secrets baubar sein.
{
  machine = "q958";
  hostName = "q958";

  disk = {
    device = "/dev/sda";
    deviceById = "/dev/disk/by-id/ata-MTFDDAK512TDL-1AW1ZABFA_19432490DAF2";
    esp = "/dev/sda1";
    root = "/dev/sda2";
    espLabel = "NIXBOOT";
  };

  network = {
    interface = "eno1";
    ip = "192.168.2.73";
    prefixLength = 24;
    gateway = "192.168.2.1";
    systemdNetworkName = "10-lan";
  };

  usb = {
    dataLabel = "NIXRECOVER";
    isoLabel = "Q958RECOVER";
  };

  recovery = {
    mode = "recover";
    autoReboot = true;
    rebootDelaySec = 45;
  };
}
