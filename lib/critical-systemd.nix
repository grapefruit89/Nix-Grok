# ---
# meta:
#   layer: 5
#   role: lib
#   purpose: Restart=always, StartLimit=0, OOM-Score für kritische Infrastruktur
#   docs:
#     - docs/AUDIT-blocky-caddy-ipv6.md
#   tags:
#     - systemd
#     - critical
# ---
{ lib, oomScore ? -900 }:

{
  Restart = lib.mkForce "always";
  RestartSec = lib.mkForce "5s";
  # Kein Start-Rate-Limit — Dienst soll nach Crash immer wieder hochkommen
  StartLimitIntervalSec = lib.mkForce 0;
  StartLimitBurst = lib.mkForce 0;
  OOMScoreAdjust = lib.mkForce oomScore;
  TimeoutStopSec = lib.mkForce "30s";
  KillMode = lib.mkForce "mixed";
}