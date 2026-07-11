#!/usr/bin/env bash
# Gesamter switch/test inkl. dry-build unter Watchdog (Zeit + CPU-Last via systemd).
set -euo pipefail

FLAKE="/etc/nixos#q958"
FLAG_DIR="/tmp/nixos-dry-build"
GIT_HASH=$(git -C /etc/nixos rev-parse HEAD 2>/dev/null || echo "no-git-$(date +%s)")
FLAG_FILE="$FLAG_DIR/ok-$GIT_HASH"
WATCHDOG_SESSION="/run/nixos-rebuild-watchdog/session"
WATCHDOG_TIMER="nixos-rebuild-watchdog.timer"
REBUILD_SENTINEL="/run/nixos/rebuild-in-progress"
LOG_DIR="/var/log/nixos-rebuild"
DRY_BUILD_MAX="${DRY_BUILD_MAX:-90}"

_resolve_nixos_rebuild() {
  local cand wrapper path
  if [ -n "${NIXOS_REBUILD_BIN:-}" ] && [ -x "$NIXOS_REBUILD_BIN" ]; then
    if ! grep -q 'nixos-rebuild-safe\.sh' "$NIXOS_REBUILD_BIN" 2>/dev/null; then
      echo "$NIXOS_REBUILD_BIN"
      return 0
    fi
  fi
  wrapper="$(command -v nixos-rebuild 2>/dev/null || true)"
  if [ -n "$wrapper" ] && [ -r "$wrapper" ]; then
    path="$(grep -oE '/nix/store/[^ ]+-nixos-rebuild[^ ]*/bin/nixos-rebuild' "$wrapper" 2>/dev/null | tail -1)"
    if [ -n "$path" ] && [ -x "$path" ]; then
      echo "$path"
      return 0
    fi
  fi
  cand="$(ls /nix/store/*-nixos-rebuild-ng-*/bin/nixos-rebuild 2>/dev/null | head -1)"
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    echo "$cand"
    return 0
  fi
  echo "nixos-rebuild nicht auflösbar (Wrapper-Rekursion)" >&2
  return 1
}

NIX_REBUILD="$(_resolve_nixos_rebuild)"
STORM_PATHS=(
  security-watchdog-switch.path
  nixos-docs-indexer-switch.path nixos-docs-indexer-flake.path nixos-docs-embedder-db.path
  nftables-geoip-update-switch.path process-delete-queue.path process-delete-queue-tierc.path
  jellyfin-transcode-cleanup.path usenet-vpn-carrier.path usenet-vpn-operstate.path
  dns-guard-secrets.path dns-guard-ddns-config.path dns-guard-ddns-updates.path
)
STORM_STATE="/run/nixos-rebuild-watchdog/storm-paths-active"

mkdir -p "$FLAG_DIR" "$LOG_DIR" /run/nixos /run/nixos-rebuild-watchdog

_watchdog_arm() {
  local action="$1"
  systemctl cat "$WATCHDOG_TIMER" &>/dev/null || return 0
  cat >"$WATCHDOG_SESSION" <<EOF
action=$action
started=$(date +%s)
pid=$$
EOF
  rm -f /run/nixos-rebuild-watchdog/high-load-since /run/nixos-rebuild-watchdog/notstop-reason
  systemctl stop "$WATCHDOG_TIMER" 2>/dev/null || true
  systemctl start "$WATCHDOG_TIMER"
  echo "⏱  Watchdog aktiv (dry-build+${action}, Zeitlimit via nixos-rebuild-watchdog.timer)"
}

_watchdog_disarm() {
  systemctl stop "$WATCHDOG_TIMER" 2>/dev/null || true
  rm -f "$WATCHDOG_SESSION" /run/nixos-rebuild-watchdog/high-load-since
}

_sentinel_on() { : >"$REBUILD_SENTINEL"; }
_sentinel_off() { rm -f "$REBUILD_SENTINEL"; }

_storm_paths_pause() {
  : >"$STORM_STATE"
  local u
  for u in "${STORM_PATHS[@]}"; do
    systemctl is-active --quiet "$u" 2>/dev/null && echo "$u" >>"$STORM_STATE"
    systemctl stop "$u" 2>/dev/null || true
  done
}

_storm_paths_resume() {
  [[ -f "$STORM_STATE" ]] || return 0
  local u
  while IFS= read -r u; do
    [[ -n "$u" ]] && systemctl start "$u" 2>/dev/null || true
  done <"$STORM_STATE"
  rm -f "$STORM_STATE"
}

_rebuild_cleanup() {
  _sentinel_off
  _storm_paths_resume
  _watchdog_disarm
}

_run_dry_build() {
  local t0=$(date +%s)
  "$NIX_REBUILD" dry-build --flake "$FLAKE" --impure
  local elapsed=$(( $(date +%s) - t0 ))
  if [ "$elapsed" -gt "$DRY_BUILD_MAX" ]; then
    echo "⚠  dry-build ${elapsed}s > ${DRY_BUILD_MAX}s (Ziel <60s)" >&2
  fi
}

_untracked=$(git -C /etc/nixos ls-files --others --exclude-standard -- '*.nix' 2>/dev/null)
if [ -n "$_untracked" ]; then
  echo "⚠  Untracked .nix — git add nötig" >&2
  exit 1
fi

case "${1:-dry}" in
  dry|--dry)
    trap _watchdog_disarm EXIT
    _watchdog_arm dry-only
    _sentinel_on
    echo "━━ dry-build ($FLAKE)"
    _run_dry_build && touch "$FLAG_FILE" && echo "✓ dry-build OK"
    _sentinel_off
    ;;
  check)
    [ -f "$FLAG_FILE" ] && echo "✓ Flag OK" || { echo "✗ kein Flag" >&2; exit 1; }
    ;;
  switch|test)
    ACTION="${1}"
    trap _rebuild_cleanup EXIT
    _watchdog_arm "$ACTION"
    _sentinel_on
    echo "━━ dry-build + $ACTION ($FLAKE) — bin=$NIX_REBUILD"
    if ! _run_dry_build; then
      echo "✗ dry-build fehlgeschlagen" >&2; exit 1
    fi
    touch "$FLAG_FILE"
    _storm_paths_pause
    REBUILD_EXIT=0
    LOG_FILE="$LOG_DIR/${ACTION}-$(date +%Y%m%d-%H%M%S).log"
    CMD=("$NIX_REBUILD" "$ACTION" --flake "$FLAKE" --impure)
    "${CMD[@]}" 2>&1 | tee "$LOG_FILE" || REBUILD_EXIT=$?
    if [ "$REBUILD_EXIT" -ne 0 ]; then
      systemctl is-failed nixos-rebuild-watchdog.service &>/dev/null && \
        echo "⚠  Notstop — /var/log/nixos-rebuild-watchdog/notstop.log" >&2
      systemctl reset-failed 2>/dev/null || true
      exit "$REBUILD_EXIT"
    fi
    systemctl reset-failed 2>/dev/null || true
    echo "✓ $ACTION OK — $LOG_FILE"
    ;;
  *)
    echo "Usage: $0 [dry|check|switch|test]" >&2
    exit 1
    ;;
esac
