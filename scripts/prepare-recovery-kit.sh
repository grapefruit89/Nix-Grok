#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Deklaratives Recovery-Kit — Manifest + optional USB + optional ISO-Flash
#   docs:
#     - docs/guides/GUIDE-recovery-zero-touch.md
# ---
set -euo pipefail

ROOT="/etc/nixos"
CONSTANTS="${ROOT}/machines/q958/recovery-constants.nix"
KIT_ENV="${RECOVERY_KIT_ENV:-${ROOT}/machines/q958/recovery-kit.env}"

usage() {
  cat <<EOF
prepare-recovery-kit — Zero-Touch Recovery vorbereiten (keine Prompts)

Deklarativ via recovery-kit.env oder Umgebungsvariablen:

  RECOVERY_YES=1                    Pflicht — bewusste Freigabe
  RECOVERY_ISO_DEV=/dev/sdb         USB für Custom Recovery-ISO (dd)
  RECOVERY_DATA_DEV=/dev/sdc        Optional: Daten-Stick NIXRECOVER
  RECOVERY_BUILD_ISO=1              ISO vor Flash bauen
  RECOVERY_FLASH_ISO=1              ISO nach Build auf RECOVERY_ISO_DEV flashen
  RECOVERY_KIT_ENV=/pfad/kit.env    Manifest-Quelle

Beispiel (ein Stick, vollautomatisch):
  RECOVERY_YES=1 RECOVERY_BUILD_ISO=1 RECOVERY_FLASH_ISO=1 \\
    RECOVERY_ISO_DEV=sdb sudo -E bash ${ROOT}/scripts/prepare-recovery-kit.sh

Beispiel (ISO + Daten-Stick für profile.local.nix):
  RECOVERY_YES=1 RECOVERY_ISO_DEV=sdb RECOVERY_DATA_DEV=sdc \\
    RECOVERY_BUILD_ISO=1 RECOVERY_FLASH_ISO=1 \\
    sudo -E bash ${ROOT}/scripts/prepare-recovery-kit.sh

Nach Vorbereitung — einzige manuelle Schritte:
  1. reboot
  2. Boot-Menü: USB (Q958RECOVER) — nicht Festplatte
  3. warten (Auto-recover + Auto-reboot)
  4. USB raus — von Festplatte booten
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

[[ -f "$KIT_ENV" ]] && { set -a; # shellcheck source=/dev/null
  source "$KIT_ENV"; set +a; }
YES="${RECOVERY_YES:-0}"
DATA_DEV="${RECOVERY_DATA_DEV:-}"
ISO_DEV="${RECOVERY_ISO_DEV:-}"
BUILD_ISO="${RECOVERY_BUILD_ISO:-0}"
FLASH_ISO="${RECOVERY_FLASH_ISO:-0}"

[[ "$YES" == "1" ]] || {
  echo "FEHLER: RECOVERY_YES=1 fehlt — bewusste Freigabe erforderlich" >&2
  usage >&2
  exit 1
}

assert_not_system_disk() {
  local dev="$1"
  dev="${dev#/dev/}"
  [[ -b "/dev/${dev}" ]] || { echo "FEHLER: /dev/${dev} nicht gefunden" >&2; exit 1; }
  [[ "$dev" != sda* ]] || { echo "FEHLER: /dev/${dev} ist Systemplatte sda" >&2; exit 1; }
  local byid
  byid="$(readlink -f "/dev/${dev}" 2>/dev/null || true)"
  if [[ "$byid" == *MTFDDAK512TDL* ]] || [[ "$byid" == *sda* ]]; then
    echo "FEHLER: /dev/${dev} zeigt auf System-SSD" >&2
    exit 1
  fi
}

generate_manifest() {
  nix-instantiate --eval --strict -E "
    let c = import ${CONSTANTS};
    in builtins.toFile \"manifest.env\" (
      \"RECOVERY_MODE=\" + c.recovery.mode + \"\\n\"
      + \"RECOVERY_DISK_BY_ID=\" + c.disk.deviceById + \"\\n\"
      + \"RECOVERY_ROOT_DEV=\" + c.disk.root + \"\\n\"
      + \"RECOVERY_ESP_DEV=\" + c.disk.esp + \"\\n\"
      + \"RECOVERY_ESP_LABEL=\" + c.disk.espLabel + \"\\n\"
      + \"RECOVERY_USB_LABEL=\" + c.usb.dataLabel + \"\\n\"
      + \"RECOVERY_AUTO_REBOOT=\" + (if c.recovery.autoReboot then \"1\" else \"0\") + \"\\n\"
      + \"RECOVERY_REBOOT_DELAY_SEC=\" + (toString c.recovery.rebootDelaySec) + \"\\n\"
      + \"RECOVERY_INTERFACE=\" + c.network.interface + \"\\n\"
    )
  " | tr -d '"'
}

write_data_usb() {
  local dev="$1"
  local mnt="/mnt/NIXRECOVER"
  local manifest_path
  manifest_path="$(generate_manifest)"
  assert_not_system_disk "$dev"
  umount "/dev/${dev#/dev/}"* 2>/dev/null || true
  mkfs.vfat -n NIXRECOVER "/dev/${dev#/dev/}"
  mkdir -p "$mnt"
  mount "/dev/${dev#/dev/}" "$mnt"
  cp "${ROOT}/scripts/emergency-bootstrap-q958.sh" "${mnt}/"
  mkdir -p "${mnt}/lib"
  cp "${ROOT}/scripts/lib/recovery-manifest.sh" "${mnt}/lib/"
  cp "$manifest_path" "${mnt}/manifest.env"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'DIR=$(cd "$(dirname "$0")" && pwd)' 'export RECOVERY_MANIFEST="${DIR}/manifest.env"' 'exec bash "${DIR}/emergency-bootstrap-q958.sh" recover' > "${mnt}/recover"
  chmod +x "${mnt}/recover" "${mnt}/emergency-bootstrap-q958.sh"
  if [[ -f "${ROOT}/machines/q958/profile.local.nix" ]]; then
    cp "${ROOT}/machines/q958/profile.local.nix" "${mnt}/"
  fi
  sync
  umount "$mnt"
  echo "OK: Daten-USB ${dev} (NIXRECOVER)"
}

flash_iso_usb() {
  local dev="$1"
  assert_not_system_disk "$dev"
  local out="${ROOT}/result-recovery-iso"
  [[ -d "$out" ]] || { echo "FEHLER: ISO nicht gebaut — RECOVERY_BUILD_ISO=1" >&2; exit 1; }
  local iso
  iso="$(find -L "$out" -maxdepth 2 -name '*.iso' | head -1)"
  [[ -n "$iso" ]] || { echo "FEHLER: keine .iso in ${out}" >&2; exit 1; }
  umount "/dev/${dev#/dev/}"* 2>/dev/null || true
  dd if="$iso" of="/dev/${dev#/dev/}" bs=4M status=progress conv=fsync oflag=sync
  sync
  echo "OK: Recovery-ISO → ${dev}"
}

echo "=== q958 Recovery-Kit (deklarativ) ==="
lsblk -o NAME,SIZE,TYPE,LABEL,MODEL /dev/sd? 2>/dev/null | grep -v '^sda ' || true

[[ "$BUILD_ISO" == "1" ]] && bash "${ROOT}/scripts/build-recovery-iso.sh"

if [[ -n "$DATA_DEV" ]]; then
  write_data_usb "$DATA_DEV"
fi

if [[ "$FLASH_ISO" == "1" ]]; then
  [[ -n "$ISO_DEV" ]] || { echo "FEHLER: RECOVERY_ISO_DEV fehlt" >&2; exit 1; }
  flash_iso_usb "$ISO_DEV"
fi

if [[ "$BUILD_ISO" != "1" && -z "$DATA_DEV" && "$FLASH_ISO" != "1" ]]; then
  echo "HINWEIS: Nichts ausgeführt — setze RECOVERY_BUILD_ISO/FLASH_ISO oder RECOVERY_DATA_DEV" >&2
  exit 1
fi

echo ""
echo "=== Fertig ==="
echo "Nächster Schritt: reboot → Boot-Menü USB (Q958RECOVER) → warten → USB raus"
