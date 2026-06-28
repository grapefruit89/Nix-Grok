#!/usr/bin/env bash
# check-api-keys.sh — testet alle API-Keys im System
# Läuft als root (liest /var/lib/secrets), gibt farbige Ausgabe
# Exit 1 wenn mindestens ein Key ungültig/nicht erreichbar
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; DIM='\033[2m'; RST='\033[0m'
FAIL=0
SKIP=0

ok()   { echo -e "${GRN}✓${RST} $1"; }
fail() { echo -e "${RED}✗${RST} $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "${DIM}–${RST} $1 (nicht konfiguriert)"; SKIP=$((SKIP+1)); }

http_check() {
  local label="$1" url="$2"
  shift 2
  local status
  status=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 "$@" "$url" 2>/dev/null || echo "000")
  case "$status" in
    2*)  ok "$label (HTTP $status)" ;;
    401) fail "$label — HTTP 401 Unauthorized (Key ungültig)" ;;
    403) fail "$label — HTTP 403 Forbidden (Key ungültig)" ;;
    000) fail "$label — Nicht erreichbar (Timeout/DNS)" ;;
    *)   fail "$label — HTTP $status" ;;
  esac
}

SECRETS="/var/lib/secrets"

echo "=== API-Key-Check $(date +%Y-%m-%d) ==="
echo ""

# ── Cloudflare DDNS ────────────────────────────────────────────────────────────
CF_TOKEN=""
[[ -f "$SECRETS/cloudflare_api_token" ]] && CF_TOKEN=$(< "$SECRETS/cloudflare_api_token")
if [[ -n "$CF_TOKEN" ]]; then
  result=$(curl -sf --max-time 10 \
    "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer $CF_TOKEN" 2>/dev/null || echo '{"success":false}')
  if echo "$result" | grep -q '"success":true'; then
    ok "Cloudflare API Token"
  else
    fail "Cloudflare API Token (ungültig oder abgelaufen)"
  fi
else
  skip "Cloudflare API Token"
fi

# ── Prowlarr ────────────────────────────────────────────────────────────────────
PROWLARR_KEY=""
[[ -f "$SECRETS/prowlarr_api_key" ]] && PROWLARR_KEY=$(< "$SECRETS/prowlarr_api_key")
if [[ -n "$PROWLARR_KEY" ]]; then
  http_check "Prowlarr" "http://localhost:5006/api/v1/system/status" \
    -H "X-Api-Key: $PROWLARR_KEY"
else
  skip "Prowlarr"
fi

# ── Sonarr ──────────────────────────────────────────────────────────────────────
SONARR_KEY=""
[[ -f "$SECRETS/sonarr_api_key" ]] && SONARR_KEY=$(< "$SECRETS/sonarr_api_key")
if [[ -n "$SONARR_KEY" ]]; then
  http_check "Sonarr" "http://localhost:5003/api/v3/system/status" \
    -H "X-Api-Key: $SONARR_KEY"
else
  skip "Sonarr"
fi

# ── Radarr ──────────────────────────────────────────────────────────────────────
RADARR_KEY=""
[[ -f "$SECRETS/radarr_api_key" ]] && RADARR_KEY=$(< "$SECRETS/radarr_api_key")
if [[ -n "$RADARR_KEY" ]]; then
  http_check "Radarr" "http://localhost:5004/api/v3/system/status" \
    -H "X-Api-Key: $RADARR_KEY"
else
  skip "Radarr"
fi

# ── SABnzbd ─────────────────────────────────────────────────────────────────────
SABNZBD_KEY=""
[[ -f "$SECRETS/sabnzbd_api_key" ]] && SABNZBD_KEY=$(< "$SECRETS/sabnzbd_api_key")
if [[ -n "$SABNZBD_KEY" ]]; then
  result=$(curl -sf --max-time 10 \
    "http://localhost:5007/api?mode=version&output=json&apikey=$SABNZBD_KEY" 2>/dev/null || echo '{}')
  if echo "$result" | grep -q '"version"'; then
    ok "SABnzbd API Key"
  else
    fail "SABnzbd API Key (keine Antwort oder ungültig)"
  fi
else
  skip "SABnzbd"
fi

# ── SceneNZBs ───────────────────────────────────────────────────────────────────
SCENENZBS_KEY=""
[[ -f "$SECRETS/scenenzbs_api_key" ]] && SCENENZBS_KEY=$(< "$SECRETS/scenenzbs_api_key")
if [[ -n "$SCENENZBS_KEY" ]]; then
  result=$(curl -sf --max-time 10 \
    "https://scenenzbs.com/api?t=caps&apikey=$SCENENZBS_KEY" 2>/dev/null || echo "")
  if echo "$result" | grep -qi '<caps'; then
    ok "SceneNZBs API Key"
  elif echo "$result" | grep -qi 'error'; then
    fail "SceneNZBs API Key (ungültig: $(echo "$result" | grep -o 'description="[^"]*"' | head -1))"
  else
    fail "SceneNZBs API Key (keine Antwort)"
  fi
else
  skip "SceneNZBs"
fi

# ── Context7 ────────────────────────────────────────────────────────────────────
CTX7_KEY=""
if [[ -f "$SECRETS/context7.env" ]]; then
  CTX7_KEY=$(grep '^CONTEXT7_API_KEY=' "$SECRETS/context7.env" 2>/dev/null | cut -d= -f2- || echo "")
fi
if [[ -n "$CTX7_KEY" ]] && ! echo "$CTX7_KEY" | grep -q '#'; then
  http_check "Context7 API Key" "https://api.context7.com/v1/health" \
    -H "Authorization: Bearer $CTX7_KEY" 2>/dev/null || \
  http_check "Context7 API Key" "https://api.context7.com/libraries?q=react" \
    -H "X-Context7-API-Key: $CTX7_KEY"
else
  skip "Context7"
fi

# ── Hermes / OpenRouter ─────────────────────────────────────────────────────────
HERMES_KEY=""
if [[ -f "$SECRETS/hermes.env" ]]; then
  HERMES_KEY=$(grep '^OPENROUTER_API_KEY=\|^OR_API_KEY=' "$SECRETS/hermes.env" 2>/dev/null | cut -d= -f2- || echo "")
fi
if [[ -n "$HERMES_KEY" ]]; then
  result=$(curl -sf --max-time 10 \
    "https://openrouter.ai/api/v1/auth/key" \
    -H "Authorization: Bearer $HERMES_KEY" 2>/dev/null || echo '{}')
  if echo "$result" | grep -q '"label"'; then
    ok "OpenRouter / Hermes API Key"
  else
    fail "OpenRouter / Hermes API Key (ungültig)"
  fi
else
  skip "OpenRouter / Hermes"
fi

# ── Ergebnis ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GRN}✓ Alle konfigurierten Keys valide${RST} ($SKIP nicht konfiguriert)"
  exit 0
else
  echo -e "${RED}✗ $FAIL Key(s) UNGÜLTIG${RST} — sofort erneuern!"
  exit 1
fi
