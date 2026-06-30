#!/usr/bin/env bash
# Einmalig ausführen NACH nixos-rebuild switch.
# Migriert *arr UIDs/GIDs von alten 3-stelligen auf neue 5xxx UIDs.
# Schritt 1: systemctl stop <services>
# Schritt 2: usermod/groupmod (dieses Script)
# Schritt 3: systemctl start <services>
set -euo pipefail

# Kein Impermanence auf q958 → /var/lib/, nicht /persist/var/lib/
BASE=/var/lib

migrate_uid() {
  local svc=$1 old=$2 new=$3
  echo "→ usermod/groupmod $svc: $old → $new"
  usermod  -u "$new" "$svc" 2>/dev/null || true
  groupmod -g "$new" "$svc" 2>/dev/null || true
  echo "→ chown $svc files in $BASE/$svc"
  find "$BASE/$svc" -xdev -exec chown -h "$new:$new" {} + 2>/dev/null || true
}

echo "=== arr UID-Migration ==="
migrate_uid sonarr   989  5003
migrate_uid radarr   978  5004
migrate_uid readarr  987  5005
migrate_uid prowlarr 969  5006
migrate_uid sabnzbd  984  5007

# sabnzbd hatte separaten GID 194 — auch migrieren
echo "→ sabnzbd GID 194 → 5007"
find "$BASE/sabnzbd" -xdev -group 194 -exec chgrp 5007 {} + 2>/dev/null || true

echo ""
echo "✓ Migration abgeschlossen. Services starten:"
echo "  sudo systemctl start sonarr radarr readarr prowlarr sabnzbd"
