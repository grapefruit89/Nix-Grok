#!/usr/bin/env bash
# dry-build: ohne Zeit-Watchdog. switch/test: Watchdog nur in der Switch-Phase.
set -euo pipefail

FLAKE="/etc/nixos#q958"
FLAG_DIR="/tmp/nixos-dry-build"
GIT_HASH=$(git -C /etc/nixos rev-parse HEAD 2>/dev/null || echo "no-git-$(date +%s)")
FLAG_FILE="$FLAG_DIR/ok-$GIT_HASH"
WATCHDOG_SESSION="/run/nixos-rebuild-watchdog/session"
WATCHDOG_TIMER="nixos-rebuild-watchdog.timer"
REBUILD_SENTINEL="/run/nixos/rebuild-in-progress"
LOG_DIR="/var/log/nixos-rebuild"
SLOW_LOG="/var/log/nixos-rebuild-watchdog/dry-build-slow.log"
CONFIG_FILE="/etc/nixos-rebuild/config.env"

# Defaults (überschreibbar via /etc/nixos-rebuild/config.env aus Nix)
DRY_BUILD_TARGET="${DRY_BUILD_TARGET:-60}"
DRY_BUILD_MAX="${DRY_BUILD_MAX:-90}"
DRY_BUILD_STRICT="${DRY_BUILD_STRICT:-0}"
SWITCH_TIMEOUT="${SWITCH_TIMEOUT:-480}"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

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
phase=switch
EOF
  rm -f /run/nixos-rebuild-watchdog/high-load-since /run/nixos-rebuild-watchdog/notstop-reason
  systemctl stop "$WATCHDOG_TIMER" 2>/dev/null || true
  systemctl start "$WATCHDOG_TIMER"
  echo "⏱  Watchdog aktiv (nur ${action}, Limit ${SWITCH_TIMEOUT}s via nixos-rebuild-watchdog.timer)"
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

_heartbeat_start() {
  HEARTBEAT_PID=""
  (
    while true; do
      sleep 30
      echo "⏳ rebuild läuft noch… $(date +%H:%M:%S)" >&2
    done
  ) &
  HEARTBEAT_PID=$!
}

_heartbeat_stop() {
  [[ -n "${HEARTBEAT_PID:-}" ]] && kill "$HEARTBEAT_PID" 2>/dev/null || true
  HEARTBEAT_PID=""
}

_rebuild_cleanup() {
  _heartbeat_stop
  _sentinel_off
  _storm_paths_resume
  _watchdog_disarm
}

_run_dry_build() {
  local t0 elapsed
  t0=$(date +%s)
  echo "━━ dry-build ($FLAKE) — Watchdog aus, Ziel <${DRY_BUILD_TARGET}s, Warnung >${DRY_BUILD_MAX}s"
  "$NIX_REBUILD" dry-build --flake "$FLAKE" --impure
  elapsed=$(( $(date +%s) - t0 ))
  echo "✓ dry-build fertig in ${elapsed}s"
  if [ "$elapsed" -gt "$DRY_BUILD_MAX" ]; then
    echo "⚠  WARNUNG: dry-build ${elapsed}s > Limit ${DRY_BUILD_MAX}s (Ziel <${DRY_BUILD_TARGET}s)" >&2
    mkdir -p "$(dirname "$SLOW_LOG")"
    echo "$(date -Is) git=${GIT_HASH} elapsed=${elapsed}s limit=${DRY_BUILD_MAX}s" >>"$SLOW_LOG"
    if [ "$DRY_BUILD_STRICT" = "1" ]; then
      echo "✗ dry-build abgebrochen (dryBuildFailOnExceed=true)" >&2
      return 1
    fi
  elif [ "$elapsed" -gt "$DRY_BUILD_TARGET" ]; then
    echo "ℹ  Hinweis: dry-build ${elapsed}s > Ziel ${DRY_BUILD_TARGET}s (unter Limit, OK)" >&2
  fi
}

_untracked=$(git -C /etc/nixos ls-files --others --exclude-standard -- '*.nix' 2>/dev/null)
if [ -n "$_untracked" ]; then
  echo "⚠  Untracked .nix — git add nötig" >&2
  exit 1
fi

case "${1:-dry}" in
  dry|--dry)
    trap '_heartbeat_stop; _sentinel_off' EXIT
    _sentinel_on
    _heartbeat_start
    _run_dry_build && touch "$FLAG_FILE" && echo "✓ dry-build OK — Flag $FLAG_FILE"
    _heartbeat_stop
    _sentinel_off
    ;;
  check)
    [ -f "$FLAG_FILE" ] && echo "✓ Flag OK ($FLAG_FILE)" || { echo "✗ kein Flag für $GIT_HASH" >&2; exit 1; }
    ;;
  switch|test)
    ACTION="${1}"
    trap _rebuild_cleanup EXIT
    _sentinel_on
    _heartbeat_start
    echo "━━ dry-build + $ACTION — bin=$NIX_REBUILD"
    if ! _run_dry_build; then
      echo "✗ dry-build fehlgeschlagen" >&2
      exit 1
    fi
    touch "$FLAG_FILE"
    _storm_paths_pause
    _watchdog_arm "$ACTION"
    _heartbeat_start
    REBUILD_EXIT=0
    LOG_FILE="$LOG_DIR/${ACTION}-$(date +%Y%m%d-%H%M%S).log"
    echo "━━ $ACTION ($FLAKE)"
    CMD=("$NIX_REBUILD" "$ACTION" --flake "$FLAKE" --impure)
    "${CMD[@]}" 2>&1 | tee "$LOG_FILE" || REBUILD_EXIT=$?
    _heartbeat_stop
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
