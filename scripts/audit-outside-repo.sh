#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Findet persistente NixOS-Artefakte außerhalb von /etc/nixos
#   docs:
#     - docs/templates/AGENTS-outside-git.md
# ---
set -euo pipefail

ROOT="/etc/nixos"
MODE="${1:-check}" # check | check-all | list | quarantine-home

# Nur persistente Pfade (pre-commit). /tmp = Agent-Scratch, separat.
PERSISTENT_ROOTS=(
  /home/jarvis
)

PRUNE=(
  -path "${ROOT}/modules/*"
  -o -path "${ROOT}/machines/*"
  -o -path "${ROOT}/lib/*"
  -o -path "${ROOT}/users/*"
  -o -path "${ROOT}/scripts/*"
  -o -path "${ROOT}/docs/*"
  -o -path "${ROOT}/packages/*"
  -o -path "${ROOT}/mcp/*"
  -o -path "${ROOT}/hosts/*"
  -o -path "${ROOT}/tools/*"
  -o -path "${ROOT}/flake.nix"
  -o -path "${ROOT}/flake.lock"
  -o -path '/home/jarvis/secrets/*'
  -o -path '/home/jarvis/.cache/*'
  -o -path '/home/jarvis/.local/*'
  -o -path '/home/jarvis/.archive*/*'
  -o -path '/home/jarvis/.grok/sessions/*'
  -o -path '/home/jarvis/.grok/marketplace-cache/*'
  -o -path '/home/jarvis/.grok/bundled/*'
  -o -path '/home/jarvis/.grok/docs/*'
  -o -path '/home/jarvis/.claude/*'
  -o -path '/home/jarvis/.cursor/*'
  -o -path '/home/jarvis/.outside-repo-quarantine/*'
  -o -path '/home/jarvis/.npm/*'
  -o -path '/home/jarvis/.nix-profile/*'
)

PATTERNS=(
  -name '*.nix'
  -o -name 'flake.lock'
  -o -name '*-patch.nix'
  -o -name 'emergency-bootstrap*.sh'
  -o -name 'cold-start*.sh'
  -o -name 'nix-disko-guard.sh'
  -o -name 'disko*.sh'
)

is_personal_note() {
  local base
  base="$(basename "$1")"
  [[ "$base" == grok-* ]] && return 0
  [[ "$base" == WICHTIG-* ]] && return 0
  [[ "$base" == AGENTS.md ]] && return 0
  [[ "$base" == set-groq-key.sh ]] && return 0
  [[ "$base" == tts-test.sh ]] && return 0
  return 1
}

scan_roots() {
  local -n roots=$1
  local -a hits=()
  while IFS= read -r -d '' f; do
    is_personal_note "$f" && continue
    hits+=("$f")
  done < <(
    find "${roots[@]}" \( "${PRUNE[@]}" \) -prune -o \
      \( "${PATTERNS[@]}" \) -type f -print0 2>/dev/null
  )
  ((${#hits[@]})) && printf '%s\n' "${hits[@]}"
}

persistent=()
while IFS= read -r line; do
  [[ -n "$line" ]] && persistent+=("$line")
done < <(scan_roots PERSISTENT_ROOTS)

if [[ "$MODE" == "check-all" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && persistent+=("$line")
  done < <(find /tmp -maxdepth 3 \( "${PATTERNS[@]}" \) -type f 2>/dev/null)
fi

if [[ ${#persistent[@]} -eq 0 ]]; then
  echo "OK: Keine persistenten NixOS-Artefakte außerhalb von ${ROOT}"
  exit 0
fi

echo "FEHLER: Persistente NixOS-Artefakte außerhalb des Git-Repos (${ROOT}):" >&2
printf '  %s\n' "${persistent[@]}" >&2
echo "" >&2
echo "→ Nach ${ROOT} verschieben + committen, oder: audit-outside-repo.sh quarantine-home" >&2

[[ "$MODE" == "list" || "$MODE" == "check-all" ]] && exit 0

if [[ "$MODE" == "quarantine-home" ]]; then
  q="/home/jarvis/.outside-repo-quarantine/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$q"
  for f in "${persistent[@]}"; do
    [[ "$f" == /home/jarvis/* ]] || continue
    rel="${f#/}"
    mkdir -p "$q/$(dirname "$rel")"
    mv "$f" "$q/$rel"
    echo "QUARANTINE: $f"
  done
  echo "Fertig: $q"
  exit 0
fi

exit 1
