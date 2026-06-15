#!/usr/bin/env bash
set -euo pipefail

ROOT=/etc/nixos
STAGE=/home/nixos

sudo mkdir -p "$ROOT/lib" "$ROOT/machines/q958" "$ROOT/users" "$ROOT/packages"
sudo cp -r "$STAGE/lib/"* "$ROOT/lib/"
sudo cp -r "$STAGE/machines/q958/"* "$ROOT/machines/q958/"
sudo cp -r "$STAGE/modules/"* "$ROOT/modules/"
sudo cp -r "$STAGE/users/"* "$ROOT/users/"
if [ -d "$STAGE/packages" ]; then
  sudo cp -r "$STAGE/packages/"* "$ROOT/packages/"
fi
sudo cp "$STAGE/configuration.nix" "$ROOT/configuration.nix"
sudo cp "$STAGE/AGENTS.md" "$ROOT/AGENTS.md"

sudo rm -f \
  "$ROOT/machines/q958/dienste-stufen.nix" \
  "$ROOT/machines/q958/zugang-sicherung.nix" \
  "$ROOT/configuration.bootstrap.nix" \
  "$ROOT/hardware-configuration.nix" \
  "$ROOT/modules/30-storage.nix.snapshot-"*

echo "deployed to $ROOT"