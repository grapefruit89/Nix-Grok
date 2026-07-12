# shellcheck shell=bash
# Deklaratives Recovery-Manifest — Quelle für emergency-bootstrap + ISO.

recovery_manifest_default_path() {
  local candidates=(
    /run/q958-recovery/manifest.env
    /recovery/manifest.env
    /mnt/NIXRECOVER/manifest.env
    /mnt/manifest.env
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

recovery_manifest_load() {
  local path="${RECOVERY_MANIFEST:-}"
  if [[ -z "$path" ]]; then
    path="$(recovery_manifest_default_path || true)"
  fi
  if [[ -n "$path" && -f "$path" ]]; then
    # shellcheck source=/dev/null
    source "$path"
  fi

  : "${RECOVERY_MODE:=recover}"
  : "${RECOVERY_DISK_BY_ID:=/dev/disk/by-id/ata-MTFDDAK512TDL-1AW1ZABFA_19432490DAF2}"
  : "${RECOVERY_ROOT_DEV:=/dev/sda2}"
  : "${RECOVERY_ESP_DEV:=/dev/sda1}"
  : "${RECOVERY_ESP_LABEL:=NIXBOOT}"
  : "${RECOVERY_USB_LABEL:=NIXRECOVER}"
  : "${RECOVERY_AUTO_REBOOT:=0}"
  : "${RECOVERY_REBOOT_DELAY_SEC:=45}"
  : "${RECOVERY_INTERFACE:=eno1}"
}

recovery_manifest_verify_disk() {
  if [[ ! -e "$RECOVERY_DISK_BY_ID" ]]; then
    echo "FEHLER: RECOVERY_DISK_BY_ID fehlt: $RECOVERY_DISK_BY_ID" >&2
    return 1
  fi
  local resolved expected
  resolved="$(readlink -f "$RECOVERY_DISK_BY_ID")"
  expected="$(readlink -f "${RECOVERY_ROOT_DEV%[0-9]}")"
  if [[ "$resolved" != "$expected" ]]; then
    echo "FEHLER: Disk-Mismatch manifest $resolved != $expected" >&2
    return 1
  fi
  echo "OK: Zielplatte verifiziert: $RECOVERY_DISK_BY_ID → $resolved"
}

recovery_usb_mount() {
  local mnt="${1:-/mnt/NIXRECOVER}"
  local dev="/dev/disk/by-label/${RECOVERY_USB_LABEL}"
  [[ -e "$dev" ]] || return 0
  mkdir -p "$mnt"
  if ! mountpoint -q "$mnt"; then
    mount "$dev" "$mnt"
  fi
  if [[ -f "${mnt}/manifest.env" && -z "${RECOVERY_MANIFEST:-}" ]]; then
    RECOVERY_MANIFEST="${mnt}/manifest.env"
    recovery_manifest_load
  fi
  if [[ -f "${mnt}/profile.local.nix" ]]; then
    export RECOVERY_PROFILE_LOCAL="${mnt}/profile.local.nix"
  fi
}
