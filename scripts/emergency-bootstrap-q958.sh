#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Live-USB Wiederherstellung q958 — deklarativ via manifest.env
#   docs:
#     - docs/EMERGENCY-RECOVERY.md
#     - docs/guides/GUIDE-recovery-zero-touch.md
# ---
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/recovery-manifest.sh"

REPO_URL="${REPO_URL:-https://github.com/grapefruit89/Nix-Grok.git}"
BRANCH="${BRANCH:-master}"
MNT="/mnt"
ROOT="${MNT}/etc/nixos"
MODE="${1:-${RECOVERY_MODE:-recover}}"
LOG="/run/q958-recovery/recover.log"

usage() {
  cat <<EOF
emergency-bootstrap-q958 — Live-USB Wiederherstellung (deklarativ)

Usage:
  emergency-bootstrap-q958.sh recover   # ext4 reparieren + Boot (Daten behalten)
  emergency-bootstrap-q958.sh install   # Neuformat — NUR mit INSTALL_CONFIRM=destroy

Manifest (optional, sonst Defaults):
  /recovery/manifest.env | /mnt/NIXRECOVER/manifest.env | RECOVERY_MANIFEST=...

Zero-Touch: Custom Recovery-ISO startet recover automatisch.
EOF
}

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

abort_if_running_from_broken_root() {
  if findmnt -rn / -o SOURCE 2>/dev/null | grep -qE '^/dev/sd'; then
    local src
    src="$(findmnt -rn / -o SOURCE)"
    if [[ "$src" == "${RECOVERY_ROOT_DEV}"* ]] || [[ "$src" == "${RECOVERY_DISK_BY_ID}"* ]]; then
      echo "FEHLER: Von kaputtem Root gebootet — NixOS Recovery-ISO/USB starten!" >&2
      exit 1
    fi
  fi
}

clone_repo() {
  if [[ -d "${ROOT}" ]] && [[ -f "${ROOT}/flake.nix" ]]; then
    log "Repo bereits unter ${ROOT}"
    return 0
  fi
  mkdir -p "${MNT}"
  if [[ ! -d "${ROOT}/.git" ]]; then
    log "Klone ${REPO_URL} (${BRANCH})…"
    git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${ROOT}"
  fi
}

recover_ext4() {
  local dev="${RECOVERY_ROOT_DEV}"
  log "=== e2fsck auf ${dev} (by-id: ${RECOVERY_DISK_BY_ID}) ==="
  recovery_manifest_verify_disk
  for sb in 32768 98304 163840 229376 294912 819200 884736 1605632; do
    log "e2fsck -b ${sb} ${dev}"
    if e2fsck -b "${sb}" -y "${dev}"; then
      log "OK: Superblock ${sb}"
      return 0
    fi
  done
  echo "FEHLER: e2fsck — alle Backup-Superblöcke fehlgeschlagen" >&2
  return 1
}

mount_recovered() {
  mount "${RECOVERY_ROOT_DEV}" "${MNT}"
  mkdir -p "${MNT}/boot"
  if ! blkid "${RECOVERY_ESP_DEV}" 2>/dev/null | grep -q TYPE=; then
    log "ESP ${RECOVERY_ESP_DEV} → vfat ${RECOVERY_ESP_LABEL}"
    mkfs.vfat -n "${RECOVERY_ESP_LABEL}" "${RECOVERY_ESP_DEV}"
  fi
  mount "${RECOVERY_ESP_DEV}" "${MNT}/boot"
}

recover_boot() {
  local sys
  sys="$(readlink -f "${MNT}/nix/var/nix/profiles/system")"
  if [[ ! -e "${sys}" ]]; then
    echo "FEHLER: Kein system-Profil unter ${MNT}/nix/var/nix/profiles/system" >&2
    exit 1
  fi
  log "Bootloader von ${sys}"
  NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root "${MNT}" -- bash -c \
    "nix-env -p /nix/var/nix/profiles/system --set ${sys} && /run/current-system/bin/switch-to-configuration boot"
}

apply_profile_local() {
  local dest="${ROOT}/machines/q958/profile.local.nix"
  if [[ -n "${RECOVERY_PROFILE_LOCAL:-}" && -f "${RECOVERY_PROFILE_LOCAL}" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "${RECOVERY_PROFILE_LOCAL}" "$dest"
    log "profile.local.nix von USB übernommen"
  fi
}

maybe_auto_reboot() {
  [[ "${RECOVERY_AUTO_REBOOT}" == "1" ]] || return 0
  log "Auto-Reboot in ${RECOVERY_REBOOT_DELAY_SEC}s — USB-Sticks entfernen wenn möglich"
  for ((i = RECOVERY_REBOOT_DELAY_SEC; i > 0; i -= 5)); do
    echo "RECOVERY FERTIG — reboot in ${i}s (USB raus)" > /dev/tty1 2>/dev/null || true
    sleep 5
  done
  reboot
}

do_recover() {
  mkdir -p /run/q958-recovery
  abort_if_running_from_broken_root
  recovery_usb_mount /mnt/NIXRECOVER
  recover_ext4
  mount_recovered
  apply_profile_local
  recover_boot
  log "=== Recovery fertig ==="
  maybe_auto_reboot
}

do_install() {
  if [[ "${INSTALL_CONFIRM:-}" != "destroy" ]]; then
    echo "FEHLER: install blockiert — INSTALL_CONFIRM=destroy erforderlich" >&2
    exit 2
  fi
  abort_if_running_from_broken_root
  clone_repo
  ensure_profile_local
  "${ROOT}/scripts/disko-q958.sh" install
  nixos-install --flake "${ROOT}#q958" --impure --no-root-passwd
  log "=== Install fertig ==="
}

ensure_profile_local() {
  local dest="${ROOT}/machines/q958/profile.local.nix"
  local example="${ROOT}/machines/q958/profile.local.nix.example"
  if [[ -n "${RECOVERY_PROFILE_LOCAL:-}" && -f "${RECOVERY_PROFILE_LOCAL}" ]]; then
    cp "${RECOVERY_PROFILE_LOCAL}" "${dest}"
  elif [[ -f "${dest}" ]]; then
    :
  elif [[ -f "${example}" ]]; then
    cp "${example}" "${dest}"
  else
    echo "WARNUNG: profile.local.nix fehlt" >&2
  fi
}

recovery_manifest_load

case "$MODE" in
  recover) do_recover ;;
  install) do_install ;;
  menu)
    if [[ -t 0 ]]; then
      echo "1) recover  2) install"
      read -rp "Wahl [1/2]: " c
      [[ "$c" == "2" ]] && do_install || do_recover
    else
      do_recover
    fi
    ;;
  help | -h | --help) usage ;;
  *) usage; exit 1 ;;
esac
