#!/usr/bin/env bash
# Nach nixos-rebuild switch: Dienste + typische Fehler prüfen.
set -euo pipefail

STUFE=$(grep -m1 'stufe =' /etc/nixos/machines/q958/profile.nix 2>/dev/null | grep -oE '[0-9]+' || echo "?")
echo "=== q958 post-switch (rollout.stufe=$STUFE) ==="

check() {
  local name="$1"
  local st
  st=$(systemctl is-active "$name" 2>/dev/null || echo "missing")
  printf "  %-22s %s\n" "$name" "$st"
}

echo ""
echo "--- Kern ---"
for s in caddy blocky pocket-id postgresql redis-valkey tailscaled; do check "$s"; done

echo ""
echo "--- Observability ---"
for s in gatus loki grafana vector; do check "$s"; done

echo ""
echo "--- Media (Stufe 6+) ---"
for s in jellyfin sonarr radarr prowlarr sabnzbd; do check "$s"; done

echo ""
echo "--- Security (Stufe 8) ---"
for s in nftables crowdsec fail2ban crowdsec-firewall-bouncer; do check "$s"; done

echo ""
echo "--- Fehler (letzte 10 min) ---"
journalctl -p err --since "10 min ago" --no-pager -n 15 2>/dev/null || true

echo ""
echo "--- nftables (wenn aktiv) ---"
if systemctl is-active nftables &>/dev/null; then
  nft list ruleset 2>/dev/null | head -20 || echo "  nft nicht verfügbar"
else
  echo "  nftables inactive"
fi