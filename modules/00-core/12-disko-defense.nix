# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Mehrschichtiger Schutz gegen destruktives disko auf Live-q958
#   tags:
#     - disko
#     - defense
#     - dr
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.core.disko-defense;
  marker = /etc/nixos/machines/q958/.live-system-no-destructive-disko;
  shadowDir = "/var/lib/q958-config-shadow";
  shadowScript = pkgs.writeShellScript "q958-config-shadow" ''
    set -euo pipefail
    dest="${shadowDir}/etc-nixos-$(date +%Y%m%d-%H%M%S).tar.zst"
    mkdir -p "${shadowDir}"
    tar -C /etc -cf - nixos \
      --exclude='nixos/.git/objects' \
      --exclude='nixos/result*' \
      --exclude='nixos/.direnv' \
      | ${pkgs.zstd}/bin/zstd -T0 -19 -o "$dest"
    ls -1t "${shadowDir}"/etc-nixos-*.tar.zst 2>/dev/null | tail -n +8 | xargs -r rm -f
    echo "OK: $dest"
  '';
in
{
  options.my.core.disko-defense = {
    enable = lib.mkEnableOption "Mehrschichtiger disko-Schutz (Live-System Tier-A)";
    immutableMarker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "chattr +i auf .live-system-no-destructive-disko (Schreibschutz Marker)";
    };
    configShadowCopy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tägliche Schattenkopie von /etc/nixos nach /var/lib/q958-config-shadow";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.diskoDefenseMarker = lib.mkIf cfg.immutableMarker ''
      if [[ -f ${marker} ]]; then
        chattr -i ${marker} 2>/dev/null || true
        chattr +i ${marker}
      fi
    '';

    systemd.services.q958-config-shadow = lib.mkIf cfg.configShadowCopy {
      description = "Schattenkopie /etc/nixos (vor disko-Unfällen)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = shadowScript;
      };
    };

    systemd.timers.q958-config-shadow = lib.mkIf cfg.configShadowCopy {
      description = "Tägliche /etc/nixos Schattenkopie";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
