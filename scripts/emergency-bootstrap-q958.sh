#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Live-USB Ein-Kommando-Wiederherstellung q958 (Recovery oder Neuinstall)
#   docs:
#     - docs/EMERGENCY-RECOVERY.md
#   tags:
#     - emergency
#     - disko
#     - dr
# ---
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/grapefruit89/Nix-Grok.git}"
BRANCH="${BRANCH:-emergency/disko-accident-2026-07-12}"
MNT="/mnt"
ROOT="${MNT}/etc/nixos"
MODE="${1:-menu}"

usage() {
  cat <<EOF
emergency-bootstrap-q958 — Live-USB Wiederherstellung

Usage:
  emergency-bootstrap-q958.sh recover   # ext4 reparieren + Boot wiederherstellen (Daten behalten)
  emergency-bootstrap-q958.sh install   # disko Neuformat + nixos-install (DATEN WEG)
  emergency-bootstrap-q958.sh menu      # Interaktiv (Default)

Voraussetzung: NixOS Minimal ISO, Netz ODER zweiter USB mit Repo-Klon.
Secrets: profile.local.nix separat auf USB bereitlegen!

One-liner (nach Push):
  curl -fsSL https://raw.githubusercontent.com/grapefruit89/Nix-Grok/${BRANCH}/scripts/emergency-bootstrap-q958.sh | sudo bash
EOF
}

abort_if_running_from_broken_root() {
  if findmnt -rn / -o SOURCE 2>/dev/null | grep -q '/dev/sda'; then
    echo "FEHLER: Von kaputtem Root gebootet — bitte NixOS Live-USB starten!" >&2
    exit 1
  fi
}

clone_repo() {
  if [[ -d "${ROOT}" ]] && [[ -f "${ROOT}/flake.nix" ]]; then
    echo "Repo bereits unter ${ROOT}"
    return 0
  fi
  mkdir -p "${MNT}"
  if [[ ! -d "${ROOT}/.git" ]]; then
    echo "Klone ${REPO_URL} (${BRANCH})…"
    git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${ROOT}"
  fi
}

recover_ext4() {
  local dev="${1:-/dev/sda2}"
  echo "=== Recovery: e2fsck auf ${dev} ==="
  echo "Versuche Backup-Superblöcke (ext4)…"
  for sb in 32768 98304 163840 229376 294912 819200 884736 1605632; do
    echo "--- e2fsck -b ${sb} ${dev} ---"
    if e2fsck -b "${sb}" -y "${dev}"; then
      echo "OK: Reparatur mit Superblock ${sb}"
      return 0
    fi
  done
  echo "FEHLER: e2fsck mit allen bekannten Backup-Superblöcken fehlgeschlagen" >&2
  return 1
}

mount_recovered() {
  mount "${1:-/dev/sda2}" "${MNT}"
  mkdir -p "${MNT}/boot"
  if ! blkid "${2:-/dev/sda1}" | grep -q TYPE=; then
    echo "Formatiere ESP ${2:-/dev/sda1}…"
    mkfs.vfat -n NIXBOOT "${2:-/dev/sda1}"
  fi
  mount "${2:-/dev/sda1}" "${MNT}/boot"
}

recover_boot() {
  local sys
  sys="$(readlink -f "${MNT}/nix/var/nix/profiles/system")"
  if [[ ! -e "${sys}" ]]; then
    echo "FEHLER: Kein system-Profil unter ${MNT}/nix/var/nix/profiles/system" >&2
    exit 1
  fi
  echo "Stelle Bootloader wieder her von: ${sys}"
  NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root "${MNT}" -- bash -c \
    "nix-env -p /nix/var/nix/profiles/system --set ${sys} && /run/current-system/bin/switch-to-configuration boot"
}

do_recover() {
  abort_if_running_from_broken_root
  recover_ext4 /dev/sda2
  mount_recovered /dev/sda2 /dev/sda1
  clone_repo
  if [[ -f /media/moritz/profile.local.nix ]]; then
    cp /media/moritz/profile.local.nix "${ROOT}/machines/q958/" || true
  fi
  recover_boot
  echo "=== Recovery fertig — reboot ==="
}

ensure_profile_local() {
  local dest="${ROOT}/machines/q958/profile.local.nix"
  local example="${ROOT}/machines/q958/profile.local.nix.example"
  if [[ -f /media/moritz/profile.local.nix ]]; then
    cp /media/moritz/profile.local.nix "${dest}"
    echo "profile.local.nix von USB übernommen"
  elif [[ -f "${dest}" ]]; then
    :
  elif [[ -f "${example}" ]]; then
    cp "${example}" "${dest}"
    echo "profile.local.nix aus .example erstellt (Platzhalter)"
  else
    echo "WARNUNG: profile.local.nix fehlt — nixos-install wird scheitern" >&2
  fi
}

do_install() {
  abort_if_running_from_broken_root
  clone_repo
  ensure_profile_local
  "${ROOT}/scripts/disko-q958.sh" install
  nixos-install --flake "${ROOT}#q958" --impure --no-root-passwd
  echo "=== Install fertig — reboot ==="
}

case "$MODE" in
  recover) do_recover ;;
  install) do_install ;;
  menu)
    echo "1) recover — Daten behalten (empfohlen wenn ext4 reparierbar)"
    echo "2) install  — Neuformat (alle Daten auf sda weg)"
    read -rp "Wahl [1/2]: " c
    [[ "$c" == "2" ]] && do_install || do_recover
    ;;
  help | -h | --help) usage ;;
  *) usage; exit 1 ;;
esac