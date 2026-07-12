#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Recovery-Skripte auf Daten-USB legen — kein langer curl auf der TTY
#   docs:
#     - docs/guides/GUIDE-recovery-live-ssh.md
# ---
set -euo pipefail

ROOT="/etc/nixos"
SRC="${ROOT}/scripts/emergency-bootstrap-q958.sh"
MOUNT="/mnt/NIXRECOVER"
LABEL="NIXRECOVER"

usage() {
  cat <<EOF
prepare-recovery-usb — Recovery-Dateien auf USB-Stick (zweiter Stick oder Daten-Partition)

Vor dem Reboot auf dem NOCH LAUFENDEN q958 ausführen:
  sudo bash ${ROOT}/scripts/prepare-recovery-usb.sh

Legt auf den Stick:
  recover              # Ein-Wort-Befehl auf Live-USB
  emergency-bootstrap-q958.sh
  profile.local.nix    # falls vorhanden

Auf dem Live-USB danach (ohne Netz, ohne curl):
  mount /dev/disk/by-label/NIXRECOVER /mnt
  bash /mnt/recover
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

if [[ ! -f "$SRC" ]]; then
  echo "FEHLER: $SRC fehlt" >&2
  exit 1
fi

echo "USB-Sticks (ohne Systemplatte sda):"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL /dev/sd? 2>/dev/null | grep -v '^sda ' || true
echo ""
read -r -p "Gerät für Recovery-USB (z.B. sdb, ohne /dev/): " dev
dev="${dev#/dev/}"
[[ -b "/dev/${dev}" ]] || { echo "FEHLER: /dev/${dev} nicht gefunden" >&2; exit 1; }
[[ "$dev" != sda* ]] || { echo "FEHLER: sda ist die Systemplatte — anderen Stick wählen" >&2; exit 1; }

read -r -p "ALLE Daten auf /dev/${dev} löschen und als NIXRECOVER formatieren? [yes/N] " ok
[[ "$ok" == "yes" ]] || { echo "Abgebrochen."; exit 0; }

sudo umount "/dev/${dev}"* 2>/dev/null || true
sudo mkfs.vfat -n "$LABEL" "/dev/${dev}"

sudo mkdir -p "$MOUNT"
sudo mount "/dev/${dev}" "$MOUNT"

sudo cp "$SRC" "${MOUNT}/emergency-bootstrap-q958.sh"
sudo tee "${MOUNT}/recover" > /dev/null << 'RECOVER'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${DIR}/emergency-bootstrap-q958.sh" recover
RECOVER
sudo chmod +x "${MOUNT}/recover" "${MOUNT}/emergency-bootstrap-q958.sh"

if [[ -f "${ROOT}/machines/q958/profile.local.nix" ]]; then
  sudo cp "${ROOT}/machines/q958/profile.local.nix" "${MOUNT}/"
  echo "OK: profile.local.nix kopiert"
fi

sudo tee "${MOUNT}/LESE-MICH.txt" > /dev/null << 'TXT'
q958 Recovery — Live-USB

1. NixOS Minimal ISO booten (Boot-Menü: USB wählen, NICHT Festplatte)
2. root einloggen (Passwort leer)
3. Netz optional — oder ohne Netz:
   mount /dev/disk/by-label/NIXRECOVER /mnt
   bash /mnt/recover
4. reboot — USB-Sticks raus — von Festplatte booten
TXT

sync
sudo umount "$MOUNT"
echo ""
echo "Fertig. Label: ${LABEL}"
echo "Live-USB: mount /dev/disk/by-label/NIXRECOVER /mnt && bash /mnt/recover"
