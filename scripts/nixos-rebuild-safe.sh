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
#   nixos-rebuild switch kann während des Builds SIGKILL bekommen wenn OOM.
#   Dieser Gate stellt sicher dass:
#     1. Ein dry-build vor jedem switch verifizierten Build nachweist
#     2. Ein Flag-File als Nachweis des erfolgreichen dry-builds gesetzt wird
#   SSH-Disconnect: wait-online-Timeout ist via 1096-vpn.nix behoben (→ ADR-2030).
#   Switch dauert <60s → keine tmux/systemd-run-Kapselung nötig.
#
# Usage:
#   sudo scripts/nixos-rebuild-safe.sh           → dry-build + Flag setzen
#   sudo scripts/nixos-rebuild-safe.sh check     → prüft ob Flag für HEAD gesetzt ist
#   sudo scripts/nixos-rebuild-safe.sh switch    → dry-build + switch (direkt, logged nach /tmp/nixos-switch.log)
#   sudo scripts/nixos-rebuild-safe.sh test      → dry-build + nixos-rebuild test
#
set -euo pipefail

FLAKE="/etc/nixos#q958"
FLAG_DIR="/tmp/nixos-dry-build"
GIT_HASH=$(git -C /etc/nixos rev-parse HEAD 2>/dev/null || echo "no-git-$(date +%s)")
FLAG_FILE="$FLAG_DIR/ok-$GIT_HASH"

mkdir -p "$FLAG_DIR"

# Nix-Flake sieht nur Git-bekannte Dateien. Neue ungetrackte .nix-Dateien sind
# für den Flake unsichtbar und verursachen "path does not exist"-Fehler beim Build.
_untracked=$(git -C /etc/nixos ls-files --others --exclude-standard -- '*.nix' 2>/dev/null)
if [ -n "$_untracked" ]; then
  echo "⚠  STOP: Neue .nix-Dateien nicht im Git-Index — für Flake unsichtbar!" >&2
  echo "$_untracked" | sed 's/^/   ?? /' >&2
  echo "" >&2
  echo "   Lösung: sudo git -C /etc/nixos add <datei(en)>" >&2
  echo "   Danach: sudo scripts/nixos-rebuild-safe.sh" >&2
  exit 1
fi
unset _untracked

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
      echo "  Switch starten mit: sudo scripts/nixos-rebuild-safe.sh switch"
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
      REBUILD_EXIT=0
      if [ "$ACTION" = "switch" ]; then
        nixos-rebuild switch --flake "$FLAKE" --impure 2>&1 | tee /tmp/nixos-switch.log || REBUILD_EXIT=$?
      else
        nixos-rebuild test --flake "$FLAKE" --impure 2>&1 | tee /tmp/nixos-test.log || REBUILD_EXIT=$?
      fi
      if [ "$REBUILD_EXIT" -ne 0 ]; then
        echo "" >&2
        echo "✗ nixos-rebuild $ACTION fehlgeschlagen (exit $REBUILD_EXIT)" >&2
        echo "" >&2
        echo "  Fehlgeschlagene Units:" >&2
        systemctl list-units --state=failed --no-pager --no-legend 2>/dev/null | sed 's/^/    /' >&2 || true
        echo "" >&2
        echo "  Details: journalctl -u <unit> -n 30 --no-pager" >&2
        exit "$REBUILD_EXIT"
      fi
      echo ""
      echo "✓ $ACTION erfolgreich — keine fehlgeschlagenen Units"
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
