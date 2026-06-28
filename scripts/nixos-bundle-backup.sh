#!/usr/bin/env bash
# nixos-bundle-backup.sh — tägliches Git-Bundle-Backup nach /mnt/fast_pool/backups/nixos/
# Läuft als root via systemd-Timer (nach Switch aktivieren)
# Fehler: kein Exit 0 bei Fehlern → systemd meldet failure → Gatus sieht failed service
set -euo pipefail

NIXOS_DIR="/etc/nixos"
BACKUP_DIR="/mnt/fast_pool/backups/nixos"
KEEP_DAYS=30
STAMP=$(date +%Y-%m-%d_%H%M)
BUNDLE="$BACKUP_DIR/nixos-config-$STAMP.bundle"

mkdir -p "$BACKUP_DIR"

# Bundle erstellen (enthält alle Branches + Tags)
git -C "$NIXOS_DIR" bundle create "$BUNDLE" --all
chmod 600 "$BUNDLE"

# Prüfen: Bundle muss valide sein (braucht ein Repo als Kontext)
git -C "$NIXOS_DIR" bundle verify "$BUNDLE" > /dev/null

# Symlink "latest" aktualisieren
ln -sf "$BUNDLE" "$BACKUP_DIR/latest.bundle"

# Alte Bundles entfernen (älter als KEEP_DAYS)
find "$BACKUP_DIR" -maxdepth 1 -name 'nixos-config-*.bundle' \
  -mtime "+$KEEP_DAYS" -delete

BUNDLE_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name 'nixos-config-*.bundle' | wc -l)
BUNDLE_SIZE=$(du -sh "$BUNDLE" | cut -f1)
echo "OK: $BUNDLE ($BUNDLE_SIZE) — $BUNDLE_COUNT Bundles behalten"
