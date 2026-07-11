#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
# Einziger Einstieg für dry-build/switch/test — ohne Extra-Parameter.
# Zeiten → /var/log/nixos-rebuild-watchdog/timings.csv (Durchschnitt automatisch).
set -euo pipefail

FLAKE="/etc/nixos#q958"
FLAG_DIR="/tmp/nixos-dry-build"
GIT_HASH=$(git -C /etc/nixos rev-parse HEAD 2>/dev/null || echo "no-git-$(date +%s)")
FLAG_FILE="$FLAG_DIR/ok-$GIT_HASH"
WATCHDOG_SESSION="/run/nixos-rebuild-watchdog/session"
WATCHDOG_TIMER="nixos-rebuild-watchdog.timer"
REBUILD_SENTINEL="/run/nixos/rebuild-in-progress"
LOG_DIR="/var/log/nixos-rebuild"
TIMINGS_CSV="/var/log/nixos-rebuild-watchdog/timings.csv"
CONFIG_FILE="/etc/nixos-rebuild/config.env"

DRY_BUILD_TARGET=60
DRY_BUILD_MAX=90
DRY_BUILD_STRICT=0
SWITCH_TIMEOUT=480
TIMING_WINDOW=30

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

_resolve_nixos_rebuild() {
  local cand wrapper path
  if [ -n "${NIXOS_REBUILD_BIN:-}" ] && [ -x "$NIXOS_REBUILD_BIN" ]; then
    if ! grep -q 'nixos-rebuild-safe' "$NIXOS_REBUILD_BIN" 2>/dev/null; then
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
  echo "nixos-rebuild nicht auflösbar" >&2
  return 1
}

NIX_REBUILD="$(_resolve_nixos_rebuild)"
STORM_PATHS=(
  security-watchdog-switch.path
  nixos-docs-indexer-switch.path nixos-docs-indexer-flake.path nixos-docs-embedder-db.path
  nftables-geoip-update-switch.path process-delete-queue.path process-delete-queue-tierc.path
  jellyfin-transcode-cleanup.path usenet-vpn-carrier.path usenet-vpn-operstate.path
  dns-guard-secrets.path dns-guard-ddns-config.path dns-guard-ddns-updates.path
  ddns-network-events.path ddns-config-changed.path
)
STORM_STATE="/run/nixos-rebuild-watchdog/storm-paths-active"
REBUILD_LOCK="/run/nixos-rebuild-watchdog/lock"
DRY_ELAPSED=0
SWITCH_ELAPSED=0

mkdir -p "$FLAG_DIR" "$LOG_DIR" /run/nixos /run/nixos-rebuild-watchdog

_timing_init() {
  mkdir -p "$(dirname "$TIMINGS_CSV")"
  if [[ ! -f "$TIMINGS_CSV" ]]; then
    echo "timestamp,git_hash,phase,seconds,exit_code,user" >"$TIMINGS_CSV"
  fi
}

_timing_record() {
  local phase="$1" seconds="$2" exit_code="$3"
  local user="${SUDO_USER:-${USER:-unknown}}"
  _timing_init
  echo "$(date -Is),${GIT_HASH},${phase},${seconds},${exit_code},${user}" >>"$TIMINGS_CSV"
}

_timing_stats() {
  local phase="$1"
  awk -F, -v phase="$phase" -v win="${TIMING_WINDOW}" '
    NR==1 { next }
    $3 == phase && $5 == 0 { rows[++n] = $4 + 0 }
    END {
      if (n == 0) { print "0 0 0 0"; exit }
      start = (n > win) ? n - win + 1 : 1
      sum = 0; min = rows[start]; max = rows[start]
      for (i = start; i <= n; i++) {
        sum += rows[i]
        if (rows[i] < min) min = rows[i]
        if (rows[i] > max) max = rows[i]
      }
      cnt = n - start + 1
      printf "%d %d %d %d", int(sum / cnt + 0.5), min, max, cnt
    }
  ' "$TIMINGS_CSV"
}

_timing_report() {
  local phase="$1" elapsed="$2"
  local avg min max cnt delta
  read -r avg min max cnt <<<"$(_timing_stats "$phase")"
  if [[ "$cnt" -eq 0 ]]; then
    echo "  ${phase}: ${elapsed}s (noch keine Vergleichsdaten)"
    return
  fi
  delta=$((elapsed - avg))
  if [[ "$delta" -gt 15 ]]; then
    echo "  ${phase}: ${elapsed}s — Ø ${avg}s (min ${min}, max ${max}, n=${cnt}) ⚠ +${delta}s über Normal" >&2
  else
    echo "  ${phase}: ${elapsed}s — Ø ${avg}s (min ${min}, max ${max}, n=${cnt})"
  fi
}

_timing_summary() {
  echo "━━ Build-Zeiten (letzte ${TIMING_WINDOW} erfolgreiche Läufe)"
  [[ "$DRY_ELAPSED" -gt 0 ]] && _timing_report "dry-build" "$DRY_ELAPSED"
  [[ "$SWITCH_ELAPSED" -gt 0 ]] && _timing_report "switch" "$SWITCH_ELAPSED"
  if [[ "$DRY_ELAPSED" -gt 0 && "$SWITCH_ELAPSED" -gt 0 ]]; then
    local total=$((DRY_ELAPSED + SWITCH_ELAPSED))
    _timing_report "total" "$total"
  fi
  echo "   Log: $TIMINGS_CSV"
}

_timing_show_all() {
  _timing_init
  echo "━━ Build-Zeiten — Historie (letzte ${TIMING_WINDOW} erfolgreiche Läufe)"
  local phase avg min max cnt last delta flag
  for phase in dry-build switch test total; do
    read -r avg min max cnt <<<"$(_timing_stats "$phase")"
    if [[ "$cnt" -eq 0 ]]; then
      echo "  ${phase}: keine Daten"
      continue
    fi
    last=$(awk -F, -v p="$phase" '$3==p {v=$4} END{print v+0}' "$TIMINGS_CSV")
    delta=$((last - avg))
    flag=""
    [[ "$delta" -gt 15 ]] && flag=" ⚠ letzter +${delta}s über Ø"
    echo "  ${phase}: Ø ${avg}s (min ${min}, max ${max}, n=${cnt}, zuletzt ${last}s)${flag}"
  done
  echo ""
  echo "Letzte Einträge:"
  tail -10 "$TIMINGS_CSV"
  echo "   Vollständig: $TIMINGS_CSV"
}

_rebuild_exclusive() {
  exec 9>"$REBUILD_LOCK"
  if ! flock -n 9; then
    echo "⚠  anderer Rebuild läuft — warte …" >&2
    flock 9
  fi
}

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
  ( while true; do sleep 30; echo "⏳ … $(date +%H:%M:%S)" >&2; done ) &
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

_check_dry_duration() {
  local elapsed="$1"
  if [[ "$elapsed" -gt "$DRY_BUILD_MAX" ]]; then
    echo "⚠  dry-build ${elapsed}s > Limit ${DRY_BUILD_MAX}s (Ziel <${DRY_BUILD_TARGET}s)" >&2
    [[ "$DRY_BUILD_STRICT" == "1" ]] && return 1
  elif [[ "$elapsed" -gt "$DRY_BUILD_TARGET" ]]; then
    echo "ℹ  dry-build ${elapsed}s > Ziel ${DRY_BUILD_TARGET}s (OK)" >&2
  fi
  return 0
}

_run_dry_build() {
  local t0 elapsed
  t0=$(date +%s)
  echo "━━ dry-build ($FLAKE)"
  "$NIX_REBUILD" dry-build --flake "$FLAKE" --impure
  elapsed=$(( $(date +%s) - t0 ))
  DRY_ELAPSED=$elapsed
  echo "✓ dry-build ${elapsed}s"
  _check_dry_duration "$elapsed"
}

_normalize_cmd() {
  case "${1:-dry}" in
    timings|stats) echo timings ;;
    dry-build|--dry) echo dry ;;
    *) echo "${1:-dry}" ;;
  esac
}

if [[ "${1:-}" == "timings" || "${1:-}" == "stats" ]]; then
  _timing_show_all
  exit 0
fi

_untracked=$(git -C /etc/nixos ls-files --others --exclude-standard -- '*.nix' 2>/dev/null)
if [ -n "$_untracked" ]; then
  echo "⚠  Untracked .nix — git add nötig" >&2
  exit 1
fi

CMD="$(_normalize_cmd "${1:-}")"

case "$CMD" in
  dry)
    _rebuild_exclusive
    trap '_heartbeat_stop; _sentinel_off' EXIT
    _sentinel_on
    _heartbeat_start
    if _run_dry_build; then
      touch "$FLAG_FILE"
      _timing_record "dry-build" "$DRY_ELAPSED" 0
      _timing_summary
      echo "✓ dry-build OK"
    else
      _timing_record "dry-build" "$DRY_ELAPSED" 1
      exit 1
    fi
    _heartbeat_stop
    _sentinel_off
    ;;
  check)
    [ -f "$FLAG_FILE" ] && echo "✓ Flag OK" || { echo "✗ kein Flag" >&2; exit 1; }
    ;;
  switch|test)
    _rebuild_exclusive
    ACTION="$CMD"
    trap _rebuild_cleanup EXIT
    _sentinel_on
    _heartbeat_start
    if ! _run_dry_build; then
      _timing_record "dry-build" "$DRY_ELAPSED" 1
      exit 1
    fi
    _timing_record "dry-build" "$DRY_ELAPSED" 0
    touch "$FLAG_FILE"
    _storm_paths_pause
    _watchdog_arm "$ACTION"
    REBUILD_EXIT=0
    LOG_FILE="$LOG_DIR/${ACTION}-$(date +%Y%m%d-%H%M%S).log"
    local_t0=$(date +%s)
    echo "━━ $ACTION ($FLAKE) — Watchdog ${SWITCH_TIMEOUT}s"
    "$NIX_REBUILD" "$ACTION" --flake "$FLAKE" --impure 2>&1 | tee "$LOG_FILE" || REBUILD_EXIT=$?
    SWITCH_ELAPSED=$(( $(date +%s) - local_t0 ))
    _heartbeat_stop
    if [[ "$ACTION" == "switch" ]]; then
      _timing_record "switch" "$SWITCH_ELAPSED" "$REBUILD_EXIT"
      _timing_record "total" "$((DRY_ELAPSED + SWITCH_ELAPSED))" "$REBUILD_EXIT"
    else
      _timing_record "test" "$SWITCH_ELAPSED" "$REBUILD_EXIT"
    fi
    _timing_summary
    if [[ "$REBUILD_EXIT" -ne 0 ]]; then
      systemctl is-failed nixos-rebuild-watchdog.service &>/dev/null && \
        echo "⚠  Notstop — /var/log/nixos-rebuild-watchdog/notstop.log" >&2
      systemctl reset-failed 2>/dev/null || true
      exit "$REBUILD_EXIT"
    fi
    systemctl reset-failed 2>/dev/null || true
    echo "✓ $ACTION OK — $LOG_FILE"
    ;;
  *)
    echo "Usage: nixos-rebuild-safe [dry|switch|test|timings|check]" >&2
    exit 1
    ;;
esac












