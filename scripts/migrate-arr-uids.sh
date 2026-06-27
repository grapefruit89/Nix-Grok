#!/usr/bin/env bash
# Einmalig ausführen NACH nixos-rebuild switch
# Migriert *arr UIDs/GIDs von alten 3-stelligen auf neue 5xxx UIDs
set -euo pipefail

migrate() {
  local svc=$1 old_uid=$2 new_uid=$3
  echo "Migrating $svc: UID/GID $old_uid → $new_uid"
  find /persist/var/lib/$svc -xdev -user $old_uid -exec chown $new_uid {} + 2>/dev/null || true
  find /persist/var/lib/$svc -xdev -group $old_uid -exec chgrp $new_uid {} + 2>/dev/null || true
}

migrate sonarr   989  5003
migrate radarr   978  5004
migrate readarr  987  5005
migrate prowlarr 969  5006
migrate sabnzbd  984  5007

# sabnzbd hatte separaten GID 194 — auch migrieren
find /persist/var/lib/sabnzbd -xdev -group 194 -exec chgrp 5007 {} + 2>/dev/null || true

echo "Migration complete. Restart services:"
echo "  systemctl restart sonarr radarr readarr prowlarr sabnzbd"
