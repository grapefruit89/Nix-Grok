#!/usr/bin/env bash
# Declarative Media Stack Locale and Application Sync Orchestrator
set -euo pipefail

echo "Syncing centralized locale settings from Nix SSoT (/users preferences)..."
echo "Target Language: ${TARGET_LANG}"
echo "Target Locale: ${TARGET_LOCALE}"

TARGET_UI_CULTURE=$(echo "$TARGET_LOCALE" | cut -d. -f1 | tr '_' '-')
TARGET_COUNTRY_CODE=$(echo "$TARGET_UI_CULTURE" | cut -d- -f2 | tr '[:lower:]' '[:upper:]')

echo "Target UI Culture: $TARGET_UI_CULTURE"
echo "Target Country Code: $TARGET_COUNTRY_CODE"

VPN_HOST="${VPN_NS_ADDRESS:-127.0.0.1}"
HOST_HOST="${HOST_BRIDGE_ADDRESS:-127.0.0.1}"
PROWLARR_PORT="${PORT_PROWLARR:-9696}"
SONARR_PORT="${PORT_SONARR:-8989}"
RADARR_PORT="${PORT_RADARR:-7878}"
SABNZBD_PORT="${PORT_SABNZBD:-8080}"

# 1. Load Declarative API keys from Local Secrets
PROWLARR_KEY=$(cat /var/lib/secrets/prowlarr_api_key 2>/dev/null || echo "prowlarr_placeholder_key")
SONARR_KEY=$(cat /var/lib/secrets/sonarr_api_key 2>/dev/null || echo "sonarr_placeholder_key")
RADARR_KEY=$(cat /var/lib/secrets/radarr_api_key 2>/dev/null || echo "radarr_placeholder_key")
SAB_KEY=$(cat /var/lib/secrets/sabnzbd_api_key 2>/dev/null || echo "sabnzbd_placeholder_key")
SCENENZBS_KEY=$(cat /var/lib/secrets/scenenzbs_api_key 2>/dev/null || echo "scenenzbs_placeholder_key")

USENET_USER="placeholder_user"
USENET_PASS="placeholder_pass"
if [ -f "/var/lib/secrets/sabnzbd_usenet_user" ]; then
  USENET_USER=$(cat /var/lib/secrets/sabnzbd_usenet_user)
fi
if [ -f "/var/lib/secrets/sabnzbd_usenet_password" ]; then
  USENET_PASS=$(cat /var/lib/secrets/sabnzbd_usenet_password)
fi

# 2. Inject Declarative API Keys and Restart Services if Drift Detected

# Prowlarr
mkdir -p /var/lib/prowlarr
if [ ! -f "/var/lib/prowlarr/config.xml" ] || ! grep -q "<ApiKey>$PROWLARR_KEY</ApiKey>" /var/lib/prowlarr/config.xml; then
  echo "Injecting declarative Prowlarr API key..."
  cat <<EOF > /var/lib/prowlarr/config.xml
<Config>
  <ApiKey>$PROWLARR_KEY</ApiKey>
</Config>
EOF
  chown -R prowlarr:prowlarr /var/lib/prowlarr || true
  echo "Restarting prowlarr service..."
  systemctl restart prowlarr.service || true
fi

# Sonarr
mkdir -p /var/lib/sonarr
if [ ! -f "/var/lib/sonarr/config.xml" ] || ! grep -q "<ApiKey>$SONARR_KEY</ApiKey>" /var/lib/sonarr/config.xml; then
  echo "Injecting declarative Sonarr API key..."
  cat <<EOF > /var/lib/sonarr/config.xml
<Config>
  <ApiKey>$SONARR_KEY</ApiKey>
</Config>
EOF
  chown -R sonarr:sonarr /var/lib/sonarr || true
  echo "Restarting sonarr service..."
  systemctl restart sonarr.service || true
fi

# Radarr
mkdir -p /var/lib/radarr
if [ ! -f "/var/lib/radarr/config.xml" ] || ! grep -q "<ApiKey>$RADARR_KEY</ApiKey>" /var/lib/radarr/config.xml; then
  echo "Injecting declarative Radarr API key..."
  cat <<EOF > /var/lib/radarr/config.xml
<Config>
  <ApiKey>$RADARR_KEY</ApiKey>
</Config>
EOF
  chown -R radarr:radarr /var/lib/radarr || true
  echo "Restarting radarr service..."
  systemctl restart radarr.service || true
fi

# Jellyfin Config Sync
JELLYFIN_XML="/var/lib/jellyfin/config/system.xml"
if [ -f "$JELLYFIN_XML" ]; then
  echo "Injecting SSoT locale into Jellyfin system.xml..."
  python3 -c "
import xml.etree.ElementTree as ET
import os
path = '$JELLYFIN_XML'
if os.path.exists(path):
    try:
        tree = ET.parse(path)
        root = tree.getroot()

        lang = root.find('PreferredMetadataLanguage')
        if lang is not None: 
            lang.text = '$TARGET_LANG'
            print('Set Jellyfin PreferredMetadataLanguage to $TARGET_LANG')
  
        cc = root.find('MetadataCountryCode')
        if cc is not None: 
            cc.text = '$TARGET_COUNTRY_CODE'
            print('Set Jellyfin MetadataCountryCode to $TARGET_COUNTRY_CODE')
  
        ui = root.find('UICulture')
        if ui is not None: 
            ui.text = '$TARGET_UI_CULTURE'
            print('Set Jellyfin UICulture to $TARGET_UI_CULTURE')
  
        tree.write(path, encoding='utf-8', xml_declaration=True)
        print('Successfully wrote Jellyfin system.xml')
    except Exception as e:
        print('Error parsing/writing Jellyfin XML: ' + str(e))
"
fi

# SABnzbd Config Sync (Language + Declarative server & categories & API keys)
SAB_INI="/var/lib/sabnzbd/sabnzbd.ini"
mkdir -p /var/lib/sabnzbd
if [ -f "$SAB_INI" ]; then
  echo "Syncing language setting in sabnzbd.ini..."
  if grep -q "language =" "$SAB_INI"; then
    sed -i 's/^language =.*/language = '"$TARGET_LANG"'/' "$SAB_INI"
  else
    sed -i '1s/^/language = '"$TARGET_LANG"'\n/' "$SAB_INI"
  fi

  # Check and inject API keys
  if grep -q "api_key =" "$SAB_INI"; then
    sed -i 's/^api_key =.*/api_key = '"$SAB_KEY"'/' "$SAB_INI"
  else
    sed -i '1s/^/api_key = '"$SAB_KEY"'\n/' "$SAB_INI"
  fi
  if grep -q "nzb_key =" "$SAB_INI"; then
    sed -i 's/^nzb_key =.*/nzb_key = '"$SAB_KEY"'/' "$SAB_INI"
  else
    sed -i '1s/^/nzb_key = '"$SAB_KEY"'\n/' "$SAB_INI"
  fi

  # Check and inject Usenet server configurations
  if ! grep -q "news.newshosting.com" "$SAB_INI"; then
    echo "Injecting declarative Usenet news server (newshosting)..."
    cat <<EOF >> "$SAB_INI"

[servers]
[[news.newshosting.com]]
name = news.newshosting.com
displayname = news.newshosting.com
host = news.newshosting.com
port = 563
timeout = 60
username = $USENET_USER
password = $USENET_PASS
connections = 100
ssl = 1
EOF
  fi

  # Check and inject download categories
  if ! grep -q "[[scenecart]]" "$SAB_INI"; then
    echo "Injecting declarative SABnzbd categories..."
    cat <<EOF >> "$SAB_INI"

[categories]
[[scenecart]]
name = scenecart
order = 4
pp = ""
script = ""
dir = scenecart
newzbin = sceneCart
priority = -100
[[audiobooks]]
name = audiobooks
order = 3
pp = ""
script = Default
dir = audiobooks
newzbin = audiobooks
[[movies]]
name = movies
order = 1
pp = ""
script = Default
dir = movies
newzbin = movies
[[tv]]
name = tv
order = 2
pp = ""
script = Default
dir = tv
newzbin = tv
[[music]]
name = music
order = 5
pp = ""
script = Default
dir = music
newzbin = music
EOF
  fi
  echo "Successfully updated sabnzbd.ini."
else
  echo "Initializing declarative sabnzbd.ini..."
  cat <<EOF > "$SAB_INI"
language = $TARGET_LANG
api_key = $SAB_KEY
nzb_key = $SAB_KEY

[servers]
[[news.newshosting.com]]
name = news.newshosting.com
displayname = news.newshosting.com
host = news.newshosting.com
port = 563
timeout = 60
username = $USENET_USER
password = $USENET_PASS
connections = 100
ssl = 1

[categories]
[[scenecart]]
name = scenecart
order = 4
pp = ""
script = ""
dir = scenecart
newzbin = sceneCart
priority = -100
[[audiobooks]]
name = audiobooks
order = 3
pp = ""
script = Default
dir = audiobooks
newzbin = audiobooks
[[movies]]
name = movies
order = 1
pp = ""
script = Default
dir = movies
newzbin = movies
[[tv]]
name = tv
order = 2
pp = ""
script = Default
dir = tv
newzbin = tv
[[music]]
name = music
order = 5
pp = ""
script = Default
dir = music
newzbin = music
EOF
  chown -R sabnzbd:sabnzbd /var/lib/sabnzbd || true
  echo "Restarting sabnzbd service to apply config..."
  systemctl restart sabnzbd.service || true
fi

# 3. APIs werden von sync.nix (wait-for-api) abgewartet

# 4. Configure SceneNZBs Indexer in Prowlarr
CURRENT_INDEXERS=$(curl -s -H "X-Api-Key: $PROWLARR_KEY" "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/indexer")
HAS_SCENE=$(echo "$CURRENT_INDEXERS" | jq '.[] | select(.name == "SceneNZBs" or .name == "Scence")')

if [ -z "$HAS_SCENE" ]; then
  echo "Configuring SceneNZBs as a declarative Usenet indexer..."
  PAYLOAD=$(cat <<EOF
{
  "name": "SceneNZBs",
  "enable": true,
  "protocol": "usenet",
  "implementation": "Newznab",
  "configContract": "NewznabSettings",
  "fields": [
    {
      "name": "baseUrl",
      "value": "https://scenenzbs.com"
    },
    {
      "name": "apiKey",
      "value": "$SCENENZBS_KEY"
    }
  ]
}
EOF
)
  curl -s -X POST \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/indexer"
  echo "SceneNZBs indexer configured successfully."
else
  echo "SceneNZBs/Scence is already present. Skipping creation."
fi

# 5. Configure Sonarr Application in Prowlarr
CURRENT_APPS=$(curl -s -H "X-Api-Key: $PROWLARR_KEY" "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/applications")
HAS_SONARR=$(echo "$CURRENT_APPS" | jq '.[] | select(.name == "Sonarr")')

if [ -z "$HAS_SONARR" ] && [ -n "$SONARR_KEY" ]; then
  echo "Configuring Sonarr application connection..."
  SONARR_PAYLOAD=$(cat <<EOF
{
  "name": "Sonarr",
  "enable": true,
  "implementation": "Sonarr",
  "implementationName": "Sonarr",
  "configContract": "SonarrSettings",
  "syncLevel": "AddAndRemoveOnly",
  "fields": [
    {
      "name": "prowlarrUrl",
      "value": "http://${VPN_HOST}:${PROWLARR_PORT}"
    },
    {
      "name": "baseUrl",
      "value": "http://${HOST_HOST}:${SONARR_PORT}"
    },
    {
      "name": "apikey",
      "value": "$SONARR_KEY"
    }
  ]
}
EOF
)
  curl -s -X POST \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "$SONARR_PAYLOAD" \
    "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/applications"
  echo "Sonarr application configured successfully."
else
  echo "Sonarr is already present or API key missing. Skipping creation."
fi

# 6. Configure Radarr Application in Prowlarr
HAS_RADARR=$(echo "$CURRENT_APPS" | jq '.[] | select(.name == "Radarr")')

if [ -z "$HAS_RADARR" ] && [ -n "$RADARR_KEY" ]; then
  echo "Configuring Radarr application connection..."
  RADARR_PAYLOAD=$(cat <<EOF
{
  "name": "Radarr",
  "enable": true,
  "implementation": "Radarr",
  "implementationName": "Radarr",
  "configContract": "RadarrSettings",
  "syncLevel": "AddAndRemoveOnly",
  "fields": [
    {
      "name": "prowlarrUrl",
      "value": "http://${VPN_HOST}:${PROWLARR_PORT}"
    },
    {
      "name": "baseUrl",
      "value": "http://${HOST_HOST}:${RADARR_PORT}"
    },
    {
      "name": "apikey",
      "value": "$RADARR_KEY"
    }
  ]
}
EOF
)
  curl -s -X POST \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "$RADARR_PAYLOAD" \
    "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/applications"
  echo "Radarr application configured successfully."
else
  echo "Radarr is already present or API key missing. Skipping creation."
fi

# 7. Configure SABnzbd Download Client in Sonarr (Category: tv)
if [ -n "$SONARR_KEY" ] && [ -n "$SAB_KEY" ]; then
  HAS_SONARR_SAB=$(curl -s -H "X-Api-Key: $SONARR_KEY" "http://127.0.0.1:${SONARR_PORT}/api/v3/downloadclient" | jq '.[] | select(.implementation == "Sabnzbd")' 2>/dev/null)
  if [ -z "$HAS_SONARR_SAB" ]; then
    echo "Configuring SABnzbd download client in Sonarr..."
    SONARR_SAB_PAYLOAD=$(cat <<EOF
{
  "enable": true,
  "name": "SABnzbd",
  "protocol": "usenet",
  "priority": 1,
  "implementationName": "SABnzbd",
  "implementation": "Sabnzbd",
  "configContract": "SabnzbdSettings",
  "fields": [
    { "name": "host", "value": "${VPN_HOST}" },
    { "name": "port", "value": ${SABNZBD_PORT} },
    { "name": "useSsl", "value": false },
    { "name": "apiKey", "value": "$SAB_KEY" },
    { "name": "category", "value": "tv" }
  ]
}
EOF
)
    curl -s -X POST \
      -H "X-Api-Key: $SONARR_KEY" \
      -H "Content-Type: application/json" \
      -d "$SONARR_SAB_PAYLOAD" \
      "http://127.0.0.1:${SONARR_PORT}/api/v3/downloadclient"
    echo "SABnzbd configured in Sonarr successfully."
  else
    echo "SABnzbd is already configured in Sonarr. Skipping."
  fi
fi

# 8. Configure SABnzbd Download Client in Radarr (Category: movies)
if [ -n "$RADARR_KEY" ] && [ -n "$SAB_KEY" ]; then
  HAS_RADARR_SAB=$(curl -s -H "X-Api-Key: $RADARR_KEY" "http://127.0.0.1:${RADARR_PORT}/api/v3/downloadclient" | jq '.[] | select(.implementation == "Sabnzbd")' 2>/dev/null)
  if [ -z "$HAS_RADARR_SAB" ]; then
    echo "Configuring SABnzbd download client in Radarr..."
    RADARR_SAB_PAYLOAD=$(cat <<EOF
{
  "enable": true,
  "name": "SABnzbd",
  "protocol": "usenet",
  "priority": 1,
  "implementationName": "SABnzbd",
  "implementation": "Sabnzbd",
  "configContract": "SabnzbdSettings",
  "fields": [
    { "name": "host", "value": "${VPN_HOST}" },
    { "name": "port", "value": ${SABNZBD_PORT} },
    { "name": "useSsl", "value": false },
    { "name": "apiKey", "value": "$SAB_KEY" },
    { "name": "category", "value": "movies" }
  ]
}
EOF
)
    curl -s -X POST \
      -H "X-Api-Key: $RADARR_KEY" \
      -H "Content-Type: application/json" \
      -d "$RADARR_SAB_PAYLOAD" \
      "http://127.0.0.1:${RADARR_PORT}/api/v3/downloadclient"
    echo "SABnzbd configured in Radarr successfully."
  else
    echo "SABnzbd is already configured in Radarr. Skipping."
  fi
fi

# 9. Sync Quality/Language Profile Assignments in Sonarr and Radarr (Unraid Migration)
if [ -n "$SONARR_KEY" ] && [ "$TARGET_LANG" = "de" ]; then
  echo "Enforcing Deutsch quality profile (ID 1) in Sonarr..."
  SERIES_LIST=$(curl -s -H "X-Api-Key: $SONARR_KEY" "http://127.0.0.1:${SONARR_PORT}/api/v3/series")
  echo "$SERIES_LIST" | jq -c '.[] | select(.qualityProfileId == 4)' 2>/dev/null | while read -r series; do
    SERIES_ID=$(echo "$series" | jq '.id')
    TITLE=$(echo "$series" | jq -r '.title')
    echo "Migrating series '$TITLE' (ID: $SERIES_ID) to Deutsch profile (ID 1)..."
    UPDATED_PAYLOAD=$(echo "$series" | jq '.qualityProfileId = 1')
    curl -s -X PUT \
      -H "X-Api-Key: $SONARR_KEY" \
      -H "Content-Type: application/json" \
      -d "$UPDATED_PAYLOAD" \
      "http://127.0.0.1:${SONARR_PORT}/api/v3/series/$SERIES_ID"
  done
fi

if [ -n "$RADARR_KEY" ] && [ "$TARGET_LANG" = "de" ]; then
  echo "Enforcing Fernseher quality profile (ID 4) in Radarr..."
  MOVIE_LIST=$(curl -s -H "X-Api-Key: $RADARR_KEY" "http://127.0.0.1:${RADARR_PORT}/api/v3/movie")
  echo "$MOVIE_LIST" | jq -c '.[] | select(.qualityProfileId == 11)' 2>/dev/null | while read -r movie; do
    MOVIE_ID=$(echo "$movie" | jq '.id')
    TITLE=$(echo "$movie" | jq -r '.title')
    echo "Migrating movie '$TITLE' (ID: $MOVIE_ID) to Fernseher profile (ID 4)..."
    UPDATED_PAYLOAD=$(echo "$movie" | jq '.qualityProfileId = 4')
    curl -s -X PUT \
      -H "X-Api-Key: $RADARR_KEY" \
      -H "Content-Type: application/json" \
      -d "$UPDATED_PAYLOAD" \
      "http://127.0.0.1:${RADARR_PORT}/api/v3/movie/$MOVIE_ID"
  done
fi

# 10. Trigger Application Sync
echo "Triggering immediate Application Sync in Prowlarr..."
curl -s -X POST \
  -H "X-Api-Key: $PROWLARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "ApplicationsSync"}' \
  "http://${VPN_HOST}:${PROWLARR_PORT}/api/v1/command"
echo "Sync command triggered. Centralized locale sync completed."
