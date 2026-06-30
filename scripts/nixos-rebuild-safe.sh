#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Dry-Run-Gate für nixos-rebuild — verhindert switch ohne verifizierten Build
#   tags:
#     - rebuild
#     - safety
#     - dry-run
# ---
#
# Warum dieses Script existiert:
#   nixos-rebuild switch stirbt mit SIGKILL (exit 137) wenn:
#     (a) OOM: Nix baut zu viele Derivations parallel
#     (b) SSH-Disconnect: Terminal-PG wird gekillt
#   Dieser Gate stellt sicher dass:
#     1. Ein dry-build vor jedem switch verifiziert wird
#     2. Die Empfehlung ist, switch in tmux auszuführen (SSH-sicher)
#     3. Ein Flag-File als Nachweis des erfolgreichen dry-builds gesetzt wird
#
# Usage:
#   sudo scripts/nixos-rebuild-safe.sh           → dry-build + Flag setzen
#   sudo scripts/nixos-rebuild-safe.sh check     → prüft ob Flag für HEAD gesetzt ist
#   sudo scripts/nixos-rebuild-safe.sh switch    → dry-build + switch in tmux (SSH-sicher)
#   sudo scripts/nixos-rebuild-safe.sh test      → dry-build + nixos-rebuild test
#
set -euo pipefail

FLAKE="/etc/nixos#q958"
FLAG_DIR="/tmp/nixos-dry-build"
GIT_HASH=$(git -C /etc/nixos rev-parse HEAD 2>/dev/null || echo "no-git-$(date +%s)")
FLAG_FILE="$FLAG_DIR/ok-$GIT_HASH"

mkdir -p "$FLAG_DIR"

case "${1:-dry}" in

  dry|--dry)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  nixos-rebuild dry-build  ($FLAKE)"
    echo "  HEAD: $GIT_HASH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if nixos-rebuild dry-build --flake "$FLAKE" --impure 2>&1; then
      touch "$FLAG_FILE"
      echo ""
      echo "✓ Dry-build erfolgreich — Flag gesetzt: $FLAG_FILE"
      echo ""
      echo "  Führe jetzt switch aus (in tmux für SSH-Sicherheit):"
      echo ""
      echo "  tmux new-session 'sudo nixos-rebuild switch --flake $FLAKE --impure 2>&1 | tee /tmp/nixos-switch.log; echo \"Exit: \$?\"; read'"
      echo ""
      echo "  Oder direkt (nur wenn SSH-Verbindung stabil ist):"
      echo "  sudo nixos-rebuild switch --flake $FLAKE --impure"
    else
      echo "" >&2
      echo "✗ Dry-build FEHLGESCHLAGEN — switch ist nicht freigegeben" >&2
      echo "  Fehler oben beheben, dann erneut: sudo scripts/nixos-rebuild-safe.sh" >&2
      exit 1
    fi
    ;;

  check)
    if [ -f "$FLAG_FILE" ]; then
      echo "✓ Flag vorhanden — dry-build für HEAD $GIT_HASH bestätigt"
      echo "  $FLAG_FILE"
      exit 0
    else
      echo "✗ Kein Flag für HEAD $GIT_HASH" >&2
      echo "  Erst ausführen: sudo scripts/nixos-rebuild-safe.sh" >&2
      exit 1
    fi
    ;;

  switch|test)
    ACTION="${1}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  nixos-rebuild dry-build  ($FLAKE)"
    echo "  HEAD: $GIT_HASH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if nixos-rebuild dry-build --flake "$FLAKE" --impure 2>&1; then
      touch "$FLAG_FILE"
      echo ""
      echo "✓ Dry-build erfolgreich — starte nixos-rebuild $ACTION …"
      echo ""
      if [ "$ACTION" = "switch" ]; then
        tmux new-session "sudo nixos-rebuild switch --flake $FLAKE --impure 2>&1 | tee /tmp/nixos-switch.log; echo \"Exit: \$?\"; read"
      else
        nixos-rebuild test --flake "$FLAKE" --impure 2>&1 | tee /tmp/nixos-test.log
      fi
    else
      echo "" >&2
      echo "✗ Dry-build FEHLGESCHLAGEN — $ACTION nicht freigegeben" >&2
      exit 1
    fi
    ;;

  *)
    echo "Usage: $0 [dry|check|switch|test]" >&2
    exit 1
    ;;
esac
