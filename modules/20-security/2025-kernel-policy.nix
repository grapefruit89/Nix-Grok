# ---
# meta:
#   layer: 3
#   role: module
#   purpose: NixOS-Optionen Kernel-Slim-Modus und Homelab-Profil
#   lib:
#     - lib/kernel/policy.nix
#   tags:
#     - kernel
#     - options
# ---
{ lib, ... }:
let
  policy = import ../../lib/kernel/policy.nix { inherit lib; };
in
{
  options.my.core.kernel-slim = {
    enable = lib.mkEnableOption "Kernel module blacklist slimming (saves RAM, reduces Angriffsfläche)";

    mode = lib.mkOption {
      type = lib.types.enum policy.modes;
      default = "homelab-strict";
      description = ''
        blank = keine Blacklist, nur host-requiredModules (Hardware-Test).
        global-only = nur Schicht A (Datacenter, Legacy, Security, Exoten-FS).
        homelab-strict = A + B + Host, inkl. Whitelist-Assertions.
        homelab-relaxed = wie strict, Homelab-Profil optional weicher.
      '';
    };

    homelabProfile = lib.mkOption {
      type = lib.types.enum policy.homelabProfiles;
      default = "none";
      description = ''
        headless-server = kein WiFi/BT/Audio/Webcam (Schicht B).
        desktop = Schicht B ohne Consumer-Blacklists (Laptop-Test).
        none = nur Schicht A + Host.
      '';
    };
  };
}
