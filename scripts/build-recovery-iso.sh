#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Zero-Touch Recovery-ISO bauen (nixosConfigurations.q958-recovery-iso)
#   docs:
#     - docs/guides/GUIDE-recovery-zero-touch.md
# ---
set -euo pipefail
ROOT="/etc/nixos"
cd "$ROOT"
OUT="${1:-result-recovery-iso}"

echo "Baue Recovery-ISO (kann 10–30 Min dauern)…"
nix build .#nixosConfigurations.q958-recovery-iso.config.system.build.isoImage \
  --impure \
  -o "$OUT"

iso="$(find -L "$OUT" -maxdepth 2 -name '*.iso' | head -1)"
echo ""
echo "OK: ${iso}"
echo "Flash: sudo dd if=${iso} of=ISO_DEV bs=4M status=progress conv=fsync oflag=sync"
