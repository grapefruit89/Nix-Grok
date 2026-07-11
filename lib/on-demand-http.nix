# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: systemd socket-proxyd on-demand HTTP — public socket, internal backend (+offset)
#   docs:
#     - docs/adr/5033-systemd-socket-on-demand.md
#   tags:
#     - on-demand
#     - systemd
#     - socket-activation
# ---
{
  lib,
  pkgs,
  internalOffset,
}:
let
  inherit (lib) mkForce;
  bindAddr = "127.0.0.1";
  proxyBin = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
  systemctl = "${pkgs.systemd}/bin/systemctl";

  internalPort = publicPort: publicPort + internalOffset;

  startBackendAndWait =
    {
      backend,
      port,
    }:
    pkgs.writeShellScript "start-${backend}" ''
      ${systemctl} start ${backend}.service
      i=0
      while [ "$i" -lt 60 ]; do
        if ${pkgs.curl}/bin/curl -fsS --max-time 1 "http://${bindAddr}:${toString port}/" >/dev/null 2>&1 \
          || ${pkgs.iproute2}/bin/ss -H -tln "sport = :${toString port}" | grep -q .; then
          exit 0
        fi
        i=$((i + 1))
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      echo "timeout waiting for backend ${backend} on :${toString port}" >&2
      exit 1
    '';
in
{
  inherit bindAddr internalOffset internalPort;

  mkProxy =
    {
      name,
      publicPort,
    }:
    let
      backend = "${name}-backend";
      iPort = internalPort publicPort;
    in
    {
      systemd.sockets.${name} = {
        description = "On-demand public socket for ${name} (:${toString publicPort})";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "${bindAddr}:${toString publicPort}";
          Accept = "no";
        };
      };

      systemd.services.${name} = {
        description = lib.mkForce "On-demand HTTP proxy for ${name} → :${toString iPort}";
        requires = lib.mkForce [ "${name}.socket" ];
        after = lib.mkForce [ "${name}.socket" ];
        partOf = lib.mkForce [ "${name}.socket" ];
        wantedBy = mkForce [ ];
        environment = lib.mkForce { };
        unitConfig = {
          StartLimitIntervalSec = lib.mkForce 0;
          StartLimitBurst = lib.mkForce 0;
        };
        serviceConfig = {
          PermissionsStartOnly = lib.mkForce true;
          Type = lib.mkForce "simple";
          ExecStartPre = lib.mkForce [
            "${startBackendAndWait {
              inherit backend;
              port = iPort;
            }}"
          ];
          ExecStart = lib.mkForce "${proxyBin} ${bindAddr}:${toString iPort}";
          BindReadOnlyPaths = lib.mkForce [ ];
          CapabilityBoundingSet = lib.mkForce [ "CAP_NET_BIND_SERVICE" ];
          DeviceAllow = lib.mkForce [ ];
          DynamicUser = lib.mkForce false;
          EnvironmentFile = lib.mkForce [ ];
          LockPersonality = lib.mkForce false;
          MemoryDenyWriteExecute = lib.mkForce false;
          OOMScoreAdjust = lib.mkForce "0";
          PrivateDevices = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
          ProtectClock = lib.mkForce false;
          ProtectControlGroups = lib.mkForce false;
          ProtectHostname = lib.mkForce false;
          ProtectKernelLogs = lib.mkForce false;
          ProtectKernelModules = lib.mkForce false;
          ProtectKernelTunables = lib.mkForce false;
          RestrictNamespaces = lib.mkForce false;
          RestrictRealtime = lib.mkForce false;
          RestrictSUIDSGID = lib.mkForce false;
          RootDirectory = lib.mkForce "";
          RuntimeDirectory = lib.mkForce "";
          StateDirectory = lib.mkForce "";
          SystemCallArchitectures = lib.mkForce "";
          SystemCallErrorNumber = lib.mkForce "";
          SystemCallFilter = lib.mkForce "";
          WorkingDirectory = lib.mkForce "";
          User = lib.mkForce "";
          Group = lib.mkForce "";
          Restart = lib.mkForce "no";
          NoNewPrivileges = lib.mkForce false;
          PrivateTmp = lib.mkForce false;
          ProtectSystem = lib.mkForce false;
          ProtectHome = lib.mkForce false;
          RestrictAddressFamilies = lib.mkForce [ ];
        };
      };
    };
}
