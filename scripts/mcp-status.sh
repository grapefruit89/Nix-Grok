#!/usr/bin/env bash
# mcp-status.sh — MCP-Stack prüfen, optional Grok/Claude starten
# Nutzung:
#   /etc/nixos/scripts/mcp-status.sh           # nur Diagnose + ####Ausgabe###
#   /etc/nixos/scripts/mcp-status.sh --grok    # danach Grok TUI
#   /etc/nixos/scripts/mcp-status.sh --claude  # danach Claude Code
set -euo pipefail

REPO="/etc/nixos"
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

LAUNCH=""
case "${1:-}" in
  --grok | -g) LAUNCH="grok" ;;
  --claude | -c) LAUNCH="claude" ;;
  --help | -h)
    echo "Usage: $0 [--grok|-g | --claude|-c]"
    exit 0
    ;;
  "") ;;
  *)
    echo "Unbekannte Option: $1 (siehe --help)" >&2
    exit 2
    ;;
esac

# PATH aus Home-Manager nachziehen (neues Terminal)
if [[ -f "${HOME}/.profile" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.profile" 2>/dev/null || true
fi
if [[ -f "${HOME}/.bashrc" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.bashrc" 2>/dev/null || true
fi

cd "$REPO"

section() { echo -e "\n${CYN}${BLD}── $1 ──${RST}"; }
ok() { echo -e "  ${GRN}✓${RST} $1"; }
warn() { echo -e "  ${YLW}!${RST} $1"; }
bad() { echo -e "  ${RED}✗${RST} $1"; }
dim() { echo -e "  ${DIM}$1${RST}"; }

# Sammeln für ####Ausgabe###
OUT_HOST="$(hostname)"
OUT_DATE="$(date -Iseconds)"
OUT_USER="$USER"
OUT_GROK=""
OUT_GROK_VER=""
OUT_CLAUDE=""
OUT_CLAUDE_VER=""
OUT_GROK_DOCTOR=""
OUT_CLAUDE_MCP=""
OUT_CREDS=()
OUT_WRAPPERS=()
OUT_SQLITE=""
OUT_INDEXER=""
OUT_MCP_JSON=""
OUT_GROK_CFG_USER=""
OUT_GROK_CFG_PROJ=""
OUT_CLAUDE_SETTINGS=""
OUT_ISSUES=()

key_ok() {
  local f="$1"
  [[ -s "$f" ]] && echo "ja" || echo "nein"
}

section "Umgebung"
dim "Repo: $REPO"
dim "User: $OUT_USER @ $OUT_HOST"
dim "Datum: $OUT_DATE"

section "Binaries & PATH"
if command -v grok >/dev/null 2>&1; then
  OUT_GROK="$(command -v grok)"
  OUT_GROK_VER="$(grok --version 2>&1 | head -1 || true)"
  ok "grok → $OUT_GROK ($OUT_GROK_VER)"
else
  bad "grok nicht im PATH"
  dim "Fix: source ~/.bashrc  oder  ~/.grok/bin/grok"
  OUT_ISSUES+=("grok: nicht im PATH")
fi

if command -v claude >/dev/null 2>&1; then
  OUT_CLAUDE="$(command -v claude)"
  OUT_CLAUDE_VER="$(claude --version 2>&1 | head -1 || true)"
  ok "claude → $OUT_CLAUDE ($OUT_CLAUDE_VER)"
else
  bad "claude nicht im PATH"
  OUT_ISSUES+=("claude: nicht im PATH")
fi

section "Credentials (nur vorhanden ja/nein)"
for spec in \
  "context7:${HOME}/.config/context7/api_key" \
  "github:${HOME}/.config/github-mcp/token" \
  "brave:${HOME}/.config/brave-search/api_key"; do
  name="${spec%%:*}"
  path="${spec#*:}"
  st="$(key_ok "$path")"
  OUT_CREDS+=("$name=$st")
  if [[ "$st" == "ja" ]]; then
    ok "$name Key"
  else
    bad "$name Key fehlt"
    OUT_ISSUES+=("credential:$name")
  fi
done

section "MCP-Wrapper (~/.local/bin)"
for w in context7-mcp brave-search-mcp github-mcp nixos-docs-mcp check-grok-mcp set-context7-api-key; do
  if [[ -x "${HOME}/.local/bin/${w}" ]] || [[ -L "${HOME}/.local/bin/${w}" ]]; then
    OUT_WRAPPERS+=("$w=ok")
    ok "$w"
  else
    OUT_WRAPPERS+=("$w=fehlt")
    bad "$w fehlt"
    OUT_ISSUES+=("wrapper:$w")
  fi
done

section "nixos-docs SQLite"
DB="/var/lib/nixos-docs-mcp/nixos_docs.sqlite"
if [[ -r "$DB" ]]; then
  OUT_SQLITE="ok ($(stat -c%s "$DB" 2>/dev/null || echo ?) bytes)"
  ok "DB lesbar: $DB"
else
  OUT_SQLITE="fehlt"
  bad "DB nicht lesbar: $DB"
  dim "Fix: sudo systemctl start nixos-docs-indexer.service"
  OUT_ISSUES+=("sqlite:fehlt")
fi

if command -v systemctl >/dev/null 2>&1; then
  OUT_INDEXER="$(systemctl is-active nixos-docs-indexer.service 2>/dev/null | tr -d '\n' | head -c 32)"
  [[ -z "$OUT_INDEXER" ]] && OUT_INDEXER="unknown"
  dim "nixos-docs-indexer: $OUT_INDEXER (oneshot = inactive nach Lauf ist normal)"
fi

section "Konfigurationsdateien"
if [[ -f "${HOME}/.grok/config.toml" ]]; then
  OUT_GROK_CFG_USER="$(grep -c '^\[mcp_servers' "${HOME}/.grok/config.toml" 2>/dev/null || echo 0) server"
  ok "~/.grok/config.toml ($OUT_GROK_CFG_USER)"
else
  OUT_GROK_CFG_USER="fehlt"
  bad "~/.grok/config.toml fehlt"
  OUT_ISSUES+=("config:grok-user")
fi

if [[ -f "$REPO/.grok/config.toml" ]]; then
  OUT_GROK_CFG_PROJ="$(grep -c '^\[mcp_servers' "$REPO/.grok/config.toml" 2>/dev/null || echo 0) server"
  ok "/etc/nixos/.grok/config.toml ($OUT_GROK_CFG_PROJ)"
else
  OUT_GROK_CFG_PROJ="fehlt"
  warn "/etc/nixos/.grok/config.toml fehlt"
fi

if [[ -f "$REPO/.mcp.json" ]]; then
  if grep -q '"mcpServers"' "$REPO/.mcp.json" 2>/dev/null; then
    OUT_MCP_JSON="ok (mcpServers-Wrapper)"
    ok ".mcp.json Format ok"
  else
    OUT_MCP_JSON="parse-fehler (fehlender mcpServers-Key)"
    bad ".mcp.json — Claude erwartet {\"mcpServers\":{...}}"
    OUT_ISSUES+=("mcp.json:parse")
  fi
else
  OUT_MCP_JSON="fehlt"
  bad ".mcp.json fehlt"
  OUT_ISSUES+=("mcp.json:fehlt")
fi

if [[ -f "${HOME}/.claude/settings.json" ]]; then
  if grep -q '"mcpServers"' "${HOME}/.claude/settings.json" 2>/dev/null; then
    n="$(grep -o '"[a-z0-9_-]*":' "${HOME}/.claude/settings.json" | wc -l)"
    OUT_CLAUDE_SETTINGS="ok"
    ok "~/.claude/settings.json hat mcpServers"
  else
    OUT_CLAUDE_SETTINGS="ohne mcpServers"
    warn "~/.claude/settings.json ohne mcpServers"
  fi
else
  OUT_CLAUDE_SETTINGS="fehlt"
  warn "~/.claude/settings.json fehlt"
fi

section "Grok MCP Doctor"
if command -v grok >/dev/null 2>&1; then
  set +e
  DOC="$(cd "$REPO" && grok mcp doctor 2>&1)"
  DOC_RC=$?
  set -e
  OUT_GROK_DOCTOR="$(echo "$DOC" | tail -3 | tr '\n' ' ')"
  echo "$DOC" | sed 's/^/  /'
  if echo "$DOC" | grep -q 'exa.*OAuth\|authorization required'; then
    warn "exa braucht einmalig OAuth: grok mcp doctor exa"
  elif [[ $DOC_RC -ne 0 ]]; then
    OUT_ISSUES+=("grok-doctor:exit-$DOC_RC")
  fi
else
  OUT_GROK_DOCTOR="übersprungen (grok fehlt)"
  dim "Übersprungen — grok nicht verfügbar"
fi

section "Claude MCP List"
if command -v claude >/dev/null 2>&1; then
  set +e
  CLIST="$(cd "$REPO" && claude mcp list 2>&1)"
  CLIST_RC=$?
  set -e
  OUT_CLAUDE_MCP="$(echo "$CLIST" | grep -E 'Connected|Failed|failing|healthy' | tr '\n' ' ' | head -c 500)"
  echo "$CLIST" | sed 's/^/  /'
  if echo "$CLIST" | grep -q 'Failed to parse'; then
    OUT_ISSUES+=("claude-mcp:parse")
  fi
  [[ $CLIST_RC -ne 0 ]] && OUT_ISSUES+=("claude-mcp:exit-$CLIST_RC")
else
  OUT_CLAUDE_MCP="übersprungen (claude fehlt)"
  dim "Übersprungen — claude nicht verfügbar"
fi

# ── ####Ausgabe### — diesen Block kopieren und an den Agenten schicken ────────
echo ""
echo -e "${BLD}════════════════════════════════════════════════════════════════${RST}"
echo -e "${BLD}####Ausgabe###${RST}  ← ab hier kopieren und an den Agenten schicken"
echo -e "${BLD}════════════════════════════════════════════════════════════════${RST}"
cat <<EOF
host=$OUT_HOST
user=$OUT_USER
datum=$OUT_DATE
repo=$REPO

grok=${OUT_GROK:-fehlt}
grok_version=${OUT_GROK_VER:-n/a}
claude=${OUT_CLAUDE:-fehlt}
claude_version=${OUT_CLAUDE_VER:-n/a}

credentials: $(IFS=,; echo "${OUT_CREDS[*]:-n/a}")
wrapper: $(IFS=,; echo "${OUT_WRAPPERS[*]:-n/a}")
sqlite=$OUT_SQLITE
indexer=$OUT_INDEXER

grok_config_user=$OUT_GROK_CFG_USER
grok_config_proj=$OUT_GROK_CFG_PROJ
mcp_json=$OUT_MCP_JSON
claude_settings=$OUT_CLAUDE_SETTINGS

grok_doctor_summary=$OUT_GROK_DOCTOR
claude_mcp_summary=$OUT_CLAUDE_MCP

probleme=$(IFS=';'; echo "${OUT_ISSUES[*]:-keine}")

# Nächste Schritte (wenn alles ok):
#   cd /etc/nixos && grok          # Grok CLI mit allen MCPs
#   cd /etc/nixos && claude        # Claude Code mit Repo-MCPs
#   grok mcp doctor exa            # einmalig Exa-OAuth
EOF
echo -e "${BLD}════════════════════════════════════════════════════════════════${RST}"
echo -e "${BLD}####/Ausgabe###${RST}"
echo -e "${BLD}════════════════════════════════════════════════════════════════${RST}"
echo ""

if [[ -n "$LAUNCH" ]]; then
  section "Starte $LAUNCH"
  cd "$REPO"
  case "$LAUNCH" in
    grok)
      dim "Tipp: /mcps in der TUI für MCP-Übersicht"
      exec grok
      ;;
    claude)
      dim "Tipp: claude mcp list für Server-Status"
      exec claude
      ;;
  esac
fi

echo -e "${DIM}Fertig. Optional starten:${RST}"
echo -e "  ${BLD}$0 --grok${RST}    → Diagnose + Grok TUI"
echo -e "  ${BLD}$0 --claude${RST}  → Diagnose + Claude Code"