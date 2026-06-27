# ---
# meta:
#   id: NIXH-05-LIB-009
#   layer: 5
#   role: lib
#   purpose: mkHardened — systemd serviceConfig Hardening-Factory (ProtectSystem, Caps, RW-Pfade)
#   tags:
#     - systemd
#     - hardening
#     - security
# ---
{ lib }:
{
  # Basis-Hardening für jeden Systemdienst. Parameter:
  #   caps  — Liste extra Capabilities (z.B. ["CAP_NET_RAW"]); default leer = keine
  #   rw    — Liste extra ReadWritePaths; default leer
  #   mdwx  — MemoryDenyWriteExecute + DevicePolicy=closed; default true
  mkHardened =
    {
      caps ? [ ],
      rw ? [ ],
      mdwx ? true,
    }:
    {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      NoNewPrivileges = true;
    }
    // lib.optionalAttrs mdwx {
      MemoryDenyWriteExecute = true;
      DevicePolicy = "closed";
    }
    // lib.optionalAttrs (caps != [ ]) {
      CapabilityBoundingSet = caps;
      AmbientCapabilities = caps;
    }
    // lib.optionalAttrs (rw != [ ]) {
      ReadWritePaths = rw;
    };
}
