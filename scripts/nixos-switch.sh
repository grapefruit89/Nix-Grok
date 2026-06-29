#!/usr/bin/env bash
# Switch-Wrapper: prüft Dry-Build-Flag, setzt Boot-Label, loggt nach /tmp
# Nutzung: nixos-switch.sh [host] [beschreibung]
# Beispiel: sudo nixos-switch.sh q958 "user-fixes dns-failsafe"
set -euo pipefail

NIXOS_DIR="/etc/nixos"
HOST="${1:-q958}"
DESC="${2:-}"
LOG="/tmp/nixos-switch-$(date +%Y%m%d_%H%M).log"
FLAG_DIR="/tmp/nixos-dry-build"
LABEL_FILE="$NIXOS_DIR/machines/$HOST/.boot-label"

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

# Boot-Label setzen: DD.MM.YYYY HH:MM [beschreibung]
TIMESTAMP=$(date +"%d.%m.%Y %H:%M")
if [ -n "$DESC" ]; then
  DESC_SLUG=$(echo "$DESC" | tr ' ' '-' | tr -cd 'a-zA-Z0-9-' | cut -c1-25)
  LABEL="${TIMESTAMP} ${DESC_SLUG}"
else
  COMMIT_SHORT=$(sudo git -C "$NIXOS_DIR" rev-parse --short HEAD 2>/dev/null || echo "nogit")
  LABEL="${TIMESTAMP} ${COMMIT_SHORT}"
fi

echo "$LABEL" | sudo tee "$LABEL_FILE" > /dev/null
echo "Boot-Label: $LABEL"
echo "Switch startet — Log: $LOG"
echo "Flake: $NIXOS_DIR#$HOST"
echo ""

sudo nixos-rebuild switch \
  --flake "$NIXOS_DIR#$HOST" \
  --impure \
  2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}

echo ""
if [ "$EXIT" -eq 0 ]; then
  echo "Switch erfolgreich. Label: $LABEL | Log: $LOG"
else
  echo "Switch FEHLGESCHLAGEN (exit $EXIT). Log: $LOG"
  exit "$EXIT"
fi
