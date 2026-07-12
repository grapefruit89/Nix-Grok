# ---
# meta:
#   layer: 3
#   role: module
#   purpose: Repo-Hygiene — Trap-AGENTS schützen, Outside-Repo-Audit
#   tags:
#     - repo-guard
#     - agents
# ---
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.core.repo-guard;
  audit = /etc/nixos/scripts/audit-outside-repo.sh;
  protect = /etc/nixos/scripts/protect-repo-traps.sh;
in
{
  options.my.core.repo-guard = {
    enable = lib.mkEnableOption "Repo-Hygiene (AGENTS-Traps, Outside-Audit)";
    auditOnTimer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Täglicher audit-outside-repo.sh check (journal)";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.repoGuardTraps = ''
      if [[ -x ${protect} ]]; then
        ${protect} || true
      fi
    '';

    systemd.services.repo-outside-audit = lib.mkIf cfg.auditOnTimer {
      description = "Audit NixOS-Artefakte außerhalb /etc/nixos";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${audit} check";
        # Nicht failen — nur loggen; pre-commit ist das harte Gate
        SuccessExitStatus = "0 1";
      };
    };

    systemd.timers.repo-outside-audit = lib.mkIf cfg.auditOnTimer {
      description = "Täglich Repo-Outside-Audit";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
