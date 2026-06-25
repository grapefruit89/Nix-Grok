#!/usr/bin/env bash
# Sync /home/nixos → /etc/nixos, build, switch (braucht root für switch).
set -euo pipefail

SRC=/home/nixos
DST=/etc/nixos

if [[ "$(id -u)" -ne 0 ]]; then
  if [[ "${1:-}" == "--trim-generations" ]]; then
    exec sudo "$SRC/tools/rebuild-q958.sh" "$@"
  fi
  echo "==> Pre-checks"
  if [[ ! -f "$SRC/machines/q958/profile.local.nix" ]]; then
    echo "FEHLER: $SRC/machines/q958/profile.local.nix fehlt"
    echo "  cp machines/q958/profile.local.nix.example machines/q958/profile.local.nix"
    exit 1
  fi
  bash "$SRC/tools/verify-no-secrets.sh"
  exec sudo "$SRC/tools/rebuild-q958.sh" "$@"
fi

if [[ "${1:-}" == "--trim-generations" ]]; then
  exec "$SRC/tools/trim-generations-q958.sh"
fi

if [[ ! -f "$SRC/machines/q958/profile.local.nix" ]]; then
  echo "FEHLER: $SRC/machines/q958/profile.local.nix fehlt"
  exit 1
fi

echo "==> Sync $SRC → $DST (ohne .git, secrets, lokale Artefakte)"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.nix-defexpr/' \
  --exclude '.grok/' \
  --exclude '.cache/' \
  --exclude '**/profile.local.nix' \
  --exclude 'secrets.sops.yaml' \
  --exclude 'stage-nixos/' \
  "$SRC/" "$DST/"

install -m 600 "$SRC/machines/q958/profile.local.nix" "$DST/machines/q958/profile.local.nix"

echo "==> nixos-rebuild build --flake $DST#q958"
nixos-rebuild build --flake "$DST#q958" --impure

echo "==> nixos-rebuild switch --flake $DST#q958"
nixos-rebuild switch --flake "$DST#q958" --impure

echo "==> Rollout: $(grep 'stufe =' "$DST/machines/q958/profile.nix" | head -1)"

if [[ -x "$SRC/tools/post-switch-check.sh" ]]; then
  bash "$SRC/tools/post-switch-check.sh"
fi