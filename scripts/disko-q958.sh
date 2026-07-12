#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: disko-Wrapper q958 — plan/install/mount für Tier-A DR (explizite CLI-Modi)
#   docs:
#     - machines/q958/disko.nix
#     - docs/EMERGENCY-RECOVERY.md
#     - docs/guides/GUIDE-disko-learning.md
#   tags:
#     - disko
#     - dr
# ---
set -euo pipefail

ROOT="/etc/nixos"
FLAKE_REF="${ROOT}#q958"
MODE="${1:-}"
PROFILE="${ROOT}/machines/q958/profile.nix"
LIVE_MARKER="${ROOT}/machines/q958/.live-system-no-destructive-disko"

DISKO_MODE_FULL="destroy,format,mount"
DISKO_MODE_FORMAT_MOUNT="format,mount"

usage() {
  cat <<EOF
disko-q958 — Tier-A Partitionierung (GPT, ext4, NIXBOOT/NIXPERSIST)

Usage (empfohlen — KI-Agenten NUR diese Subbefehle):
  disko-q958.sh plan            # Skript aus Nix-Store anzeigen (SICHER — führt nichts aus!)
  disko-q958.sh vm              # Interaktive VM (sicher zum Lernen)
  disko-q958.sh install         # destroy + format + mount (NUR Live-USB/ISO!)

  disko-q958.sh format|format-mount|mount|destroy  # NUR Live-USB/ISO!

DEPRECATED (exit 2): disko-q958.sh disko
VERBOTEN auf Live-System: nix run github:nix-community/disko -- script …

Siehe: docs/EMERGENCY-RECOVERY.md
EOF
}

tier_a_device() {
  grep -E 'device = "/dev/' "$PROFILE" 2>/dev/null | head -1 | sed -n 's/.*device = "\([^"]*\)".*/\1/p' || echo "/dev/sda"
}

root_on_tier_a() {
  local dev root_src
  dev="$(tier_a_device)"
  root_src="$(findmnt -rn / -o SOURCE 2>/dev/null || true)"
  [[ -n "$root_src" && "$root_src" == "${dev}"* ]]
}

live_system_guard() {
  [[ -f "$LIVE_MARKER" ]] || return 0
  if root_on_tier_a; then
    return 0
  fi
  return 1
}

abort_if_live_destructive() {
  if live_system_guard; then
    echo "ABBRUCH [LIVE-GUARD]: $(tier_a_device) ist Root dieses Systems." >&2
    echo "  Destruktive disko-Modi nur von NixOS Live-USB." >&2
    echo "  Sicher: disko-q958.sh plan | disko-q958.sh vm" >&2
    echo "  Recovery: docs/EMERGENCY-RECOVERY.md" >&2
    exit 99
  fi
}

nix_disko() {
  local arg
  local allow_dry=0
  for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && allow_dry=1
  done
  if live_system_guard && [[ "$allow_dry" -eq 0 ]]; then
    echo "ABBRUCH [LIVE-GUARD]: disko auf Live-System — nur --dry-run (plan) erlaubt." >&2
    exit 99
  fi
  nix --extra-experimental-features 'nix-command flakes' \
    run github:nix-community/disko -- --flake "$FLAKE_REF" "$@"
}

show_plan_script() {
  local out script_path
  out="$(nix_disko --dry-run --mode "$DISKO_MODE_FULL" 2>&1)"
  echo "$out"
  script_path="$(echo "$out" | rg -o '/nix/store/[a-z0-9]+-disko-destroy-format-mount/bin/disko-destroy-format-mount' | tail -1 || true)"
  if [[ -z "$script_path" || ! -f "$script_path" ]]; then
    echo "FEHLER: disko-Skript-Pfad nicht gefunden" >&2
    exit 1
  fi
  echo ""
  echo "=== generiertes Skript (Store — NICHT ausführen!) ==="
  echo "# Quelle: $script_path"
  cat "$script_path"
}

reject_deprecated_disko() {
  echo "FEHLER: Subbefehl 'disko' ist deprecated." >&2
  exit 2
}

case "$MODE" in
  plan)
    echo "=== disko plan (sicher: dry-run + Store-cat) ==="
    show_plan_script
    ;;
  install)
    abort_if_live_destructive
    echo "WARNUNG: destroy+format+mount. Ctrl+C in 5s…" >&2
    sleep 5
    nix_disko --mode "$DISKO_MODE_FULL" --yes-wipe-all-disks
    ;;
  destroy | format | format-mount | mount)
    abort_if_live_destructive
    case "$MODE" in
      destroy) nix_disko --mode destroy --yes-wipe-all-disks ;;
      format) nix_disko --mode format ;;
      format-mount) nix_disko --mode "$DISKO_MODE_FORMAT_MOUNT" ;;
      mount) nix_disko --mode mount ;;
    esac
    ;;
  vm)
    nix --extra-experimental-features 'nix-command flakes' run "${ROOT}#nixosConfigurations.q958-disko-vm.config.system.build.vmWithDisko"
    ;;
  disko) reject_deprecated_disko ;;
  help | -h | --help | "") usage ;;
  *)
    echo "Unbekannter Modus: $MODE" >&2
    usage >&2
    exit 1
    ;;
esac