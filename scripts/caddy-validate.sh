#!/usr/bin/env bash
# Validiert die generierte Caddy-Konfiguration via 'caddy adapt' bevor ein rebuild.
# Pflicht-Step bei jeder Änderung an Caddy-relevanten Nix-Dateien.
set -euo pipefail

CADDY_BIN=$(find /nix/store -name "caddy" -path "*/bin/caddy" -type f 2>/dev/null | head -1)
if [ -z "$CADDY_BIN" ]; then
  echo "ERROR: caddy binary nicht im nix store gefunden" >&2
  exit 1
fi

TMPFILE=$(mktemp /tmp/caddy-validate-XXXXXX.caddyfile)
trap 'rm -f "$TMPFILE"' EXIT

echo "Evaluiere Caddy-Config aus NixOS..."
{
  printf '{\n'
  sudo nix eval --impure --raw \
    /etc/nixos#nixosConfigurations.q958.config.services.caddy.globalConfig 2>/dev/null
  printf '\n}\n'
} > "$TMPFILE"

echo "Validiere Caddyfile-Syntax..."
if sudo "$CADDY_BIN" adapt --config "$TMPFILE" --adapter caddyfile > /dev/null 2>&1; then
  echo "✓ Caddy-Syntax valide"
else
  echo "✗ Caddy-Syntax-Fehler:" >&2
  sudo "$CADDY_BIN" adapt --config "$TMPFILE" --adapter caddyfile 2>&1 >&2
  exit 1
fi
