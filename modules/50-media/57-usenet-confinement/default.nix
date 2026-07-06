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
  options.my.services.usenet-confinement.enable =
    lib.mkEnableOption "Usenet VPN-Sandbox (SABnzbd + Prowlarr via Privado WireGuard)";

  config = lib.mkIf cfg.enable {
    environment.etc."usenet-resolv.conf".text = lib.concatMapStrings (
      dns: "nameserver ${dns}\n"
    ) privado.dns;

    systemd.services.sabnzbd = sandboxAttrs;
    systemd.services.prowlarr = sandboxAttrs;
  };
}
