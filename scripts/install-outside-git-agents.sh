#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: AGENTS.md in bekannte Nicht-Repo-Verzeichnisse legen (Trap-Ordner)
#   docs:
#     - docs/templates/AGENTS-outside-git.md
# ---
set -euo pipefail

ROOT="/etc/nixos"
TEMPLATE="${ROOT}/docs/templates/AGENTS-outside-git.md"
SECRETS_TEMPLATE="${ROOT}/docs/templates/AGENTS-secrets-dir.md"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "FEHLER: $TEMPLATE fehlt" >&2
  exit 1
fi

install_agents() {
  local dir="$1"
  local src="${2:-$TEMPLATE}"
  [[ -d "$dir" ]] || return 0
  cp "$src" "${dir}/AGENTS.md"
  echo "OK: ${dir}/AGENTS.md"
}

install_agents /home/jarvis
install_agents /home/jarvis/bin
install_agents /home/jarvis/nixos

if [[ -f "$SECRETS_TEMPLATE" ]]; then
  install_agents /home/jarvis/secrets "$SECRETS_TEMPLATE"
fi

echo "Fertig. Kanonisches Repo: ${ROOT}"