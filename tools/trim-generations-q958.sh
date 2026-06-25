#!/usr/bin/env bash
# Einmaliges Aufräumen der NixOS-Generationen (q958).
# - GC-Root für boot.pinnedGenerations (Store-Pfade der Baselines)
# - Löscht Mittel-Generationen 87–91 (HA-Debug-Spam vom 17.06.)
# Braucht root: tools/rebuild-q958.sh --trim-generations
set -euo pipefail

SRC=/home/nixos
PROFILE=/nix/var/nix/profiles/system
PROFILE_NIX="$SRC/machines/q958/profile.nix"
GCROOTS=/nix/var/nix/gcroots/q958-pinned

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$SRC/tools/trim-generations-q958.sh" "$@"
fi

if [[ ! -f "$PROFILE_NIX" ]]; then
  PROFILE_NIX=/etc/nixos/machines/q958/profile.nix
fi

DELETE_GENS=(87 88 89 90 91)

PIN_LINE=$(grep -E 'pinnedGenerations\s*=' "$PROFILE_NIX" | head -1 || true)
if [[ -n "$PIN_LINE" ]]; then
  read -r -a PINNED <<< "$(echo "$PIN_LINE" | grep -oE '[0-9]+' | tr '\n' ' ')"
else
  PINNED=(85 86)
fi

mkdir -p "$GCROOTS"

echo "==> GC-Root für Baseline-Generationen: ${PINNED[*]}"
for g in "${PINNED[@]}"; do
  link="/nix/var/nix/profiles/system-${g}-link"
  if [[ -L "$link" ]]; then
    ln -sfn "$(readlink -f "$link")" "${GCROOTS}/generation-${g}"
    echo "    Gen ${g}: $(readlink -f "$link")"
  else
    echo "    Gen ${g}: Profil-Link fehlt — übersprungen"
  fi
done

echo "==> Lösche Mittel-Generationen: ${DELETE_GENS[*]}"
for g in "${DELETE_GENS[@]}"; do
  if nix-env -p "$PROFILE" --list-generations | grep -qE "^[[:space:]]*${g}[[:space:]]"; then
    nix-env -p "$PROFILE" --delete-generations "$g"
    echo "    Gen ${g}: gelöscht"
  fi
done

echo "==> nix-store --gc"
nix-store --gc

echo "==> Verbleibende Generationen:"
nix-env -p "$PROFILE" --list-generations
echo "==> Boot-Einträge: $(ls -1 /boot/loader/entries/*.conf 2>/dev/null | wc -l)"