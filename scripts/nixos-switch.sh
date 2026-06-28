#!/usr/bin/env bash
# Switch-Wrapper: prüft Dry-Build-Flag, loggt nach /tmp, kein tmux nötig
set -euo pipefail

NIXOS_DIR="/etc/nixos"
HOST="${1:-q958}"
LOG="/tmp/nixos-switch-$(date +%Y%m%d_%H%M).log"
FLAG_DIR="/tmp/nixos-dry-build"

LAST_OK=$(ls -t "$FLAG_DIR"/ok-* 2>/dev/null | head -1 || true)
if [ -z "$LAST_OK" ]; then
  echo "FEHLER: Kein Dry-Build-Flag gefunden. Erst ausführen:"
  echo "  sudo $NIXOS_DIR/scripts/nixos-rebuild-safe.sh"
  exit 1
fi

HEAD=$(sudo git -C "$NIXOS_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
if [[ "$LAST_OK" != *"$HEAD"* ]]; then
  echo "FEHLER: Dry-Build-Flag ist von einem älteren Commit."
  echo "  Flag:   $LAST_OK"
  echo "  HEAD:   $HEAD"
  echo "Erst neu dry-builden: sudo $NIXOS_DIR/scripts/nixos-rebuild-safe.sh"
  exit 1
fi

echo "Switch startet — Log: $LOG"
echo "Flake: $NIXOS_DIR#$HOST"
echo ""

sudo nixos-rebuild switch --flake "$NIXOS_DIR#$HOST" --impure 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}

echo ""
if [ "$EXIT" -eq 0 ]; then
  echo "Switch erfolgreich. Log: $LOG"
else
  echo "Switch FEHLGESCHLAGEN (exit $EXIT). Log: $LOG"
  exit "$EXIT"
fi
