#!/usr/bin/env bash
# Setzt chattr +i auf AGENTS.md Trap-Dateien — KI kann Warnung nicht leise löschen.
set -euo pipefail
ROOT="/etc/nixos"
TRAPS=(
  /home/moritz/AGENTS.md
  /home/moritz/bin/AGENTS.md
  /home/moritz/secrets/AGENTS.md
)
bash "${ROOT}/scripts/install-outside-git-agents.sh"
for f in "${TRAPS[@]}"; do
  [[ -f "$f" ]] || continue
  chattr -i "$f" 2>/dev/null || true
  chattr +i "$f"
  echo "immutable: $f"
done
