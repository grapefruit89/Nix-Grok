#!/usr/bin/env bash
# Vollbackup: Git-Repo + gitignored Secrets → USB /NixmitGrok_USB
set -euo pipefail

SRC=/home/nixos
USB_MOUNT="${USB_MOUNT:-/mnt/usbinspect}"
DEST="${USB_MOUNT}/NixmitGrok_USB"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
GIT_BIN="${GIT_BIN:-/run/current-system/sw/bin/git}"

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$SRC/tools/backup-to-usb.sh" "$@"
fi

if ! mountpoint -q "$USB_MOUNT"; then
  echo "FEHLER: USB nicht gemountet unter $USB_MOUNT"
  exit 1
fi

if [[ ! -d "$SRC/.git" ]]; then
  echo "FEHLER: Kein Git-Repo unter $SRC (.git fehlt)"
  exit 1
fi

REPO_USER=$(stat -c '%U' "$SRC")

run_git() {
  # sudo kann GIT_DIR/GIT_WORK_TREE vom Aufrufer durchreichen → explizit leeren
  local -a env_clean=(
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX
  )
  if [[ "$(id -u)" -eq 0 && "$REPO_USER" != "root" ]]; then
    runuser -u "$REPO_USER" -- "${env_clean[@]}" "$GIT_BIN" -C "$SRC" "$@"
  else
    "${env_clean[@]}" "$GIT_BIN" -C "$SRC" "$@"
  fi
}

if ! run_git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "FEHLER: $SRC ist für $(id -un) kein gültiges Git-Repository"
  exit 1
fi

GIT_REV=$(run_git rev-parse --short HEAD)

echo "==> USB rw remount"
mount -o remount,rw "$USB_MOUNT" 2>/dev/null || mount -o remount,rw /dev/sdb1 "$USB_MOUNT"

mkdir -p "$DEST"

# mktemp als root → nixos kann nicht in root-owned Datei schreiben
BUNDLE_TMP=$(runuser -u "$REPO_USER" -- mktemp "/tmp/repo-${STAMP}.XXXXXX.bundle")
trap 'rm -f "$BUNDLE_TMP"' EXIT

echo "==> Git bundle (als $REPO_USER) → $DEST/repo-${STAMP}.bundle"
run_git bundle create "$BUNDLE_TMP" --all
cp -f "$BUNDLE_TMP" "$DEST/repo-${STAMP}.bundle"

echo "==> Git-Archiv (ohne .git) → $DEST/nixos-tree-${STAMP}.tar.zst"
tar -C "$SRC" \
  --exclude='.git' \
  --exclude='.cache' \
  --exclude='.grok' \
  --exclude='backups' \
  --exclude='result' \
  --exclude='result-*' \
  -cf - . | zstd -19 -T0 -o "$DEST/nixos-tree-${STAMP}.tar.zst"

echo "==> Lokale Secrets (gitignored)"
SECRETS_ARCHIVE="$DEST/local-secrets-${STAMP}.tar.zst"
tar -C "$SRC" -cf - \
  machines/q958/profile.local.nix \
  2>/dev/null | zstd -19 -T0 -o "$SECRETS_ARCHIVE" || true

if [[ -d /var/lib/secrets ]]; then
  tar -C /var/lib -cf - secrets 2>/dev/null | zstd -19 -T0 -o "$DEST/var-lib-secrets-${STAMP}.tar.zst" || true
fi

echo "==> User dotfiles (.config/.local, ohne Cache)"
DOTFILES_ARCHIVE="$DEST/user-dotfiles-${STAMP}.tar.zst"
tar -C "$SRC" -cf - \
  --exclude='.cache' \
  --exclude='.config/cursor' \
  --exclude='.local/share/Trash' \
  .config .local \
  2>/dev/null | zstd -19 -T0 -o "$DOTFILES_ARCHIVE" || true

if [[ -f /home/nixos/.ssh/id_ed25519_github ]]; then
  install -d -m 700 "$DEST/ssh"
  install -m 600 /home/nixos/.ssh/id_ed25519_github "$DEST/ssh/id_ed25519_github"
  [[ -f /home/nixos/.ssh/id_ed25519_github.pub ]] && \
    install -m 644 /home/nixos/.ssh/id_ed25519_github.pub "$DEST/ssh/id_ed25519_github.pub"
fi

cat > "$DEST/README-${STAMP}.txt" <<EOF
NixmitGrok_USB Backup — ${STAMP}
Host: $(hostname)
Git: ${GIT_REV} (main)
Inhalt:
  - repo-*.bundle     → git clone / git pull aus Bundle
  - nixos-tree-*.tar.zst → Arbeitsbaum ohne .git
  - local-secrets-*.tar.zst → profile.local.nix (NIEMALS nach GitHub)
  - var-lib-secrets-*.tar.zst → /var/lib/secrets Runtime
  - user-dotfiles-*.tar.zst → ~/.config + ~/.local (ohne .cache)
  - ssh/ → Deploy-Key GitHub (falls vorhanden)
Restore profile.local:
  tar -I zstd -xf local-secrets-*.tar.zst -C /home/nixos
Restore dotfiles:
  tar -I zstd -xf user-dotfiles-*.tar.zst -C /home/nixos
EOF

run_git rev-parse HEAD > "$DEST/git-rev-${STAMP}.txt"

sync
echo "==> Fertig: $DEST"
ls -lh "$DEST"