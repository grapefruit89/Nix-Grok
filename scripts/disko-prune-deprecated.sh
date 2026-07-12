#!/usr/bin/env bash
# ---
# meta:
#   role: script
#   purpose: Entfernt DEPRECATED-DISKO-Marker-Blöcke nach erfolgreicher verify
#   docs:
#     - machines/q958/disko-deprecations.json
#   tags:
#     - disko
#     - prune
# ---
set -euo pipefail

ROOT="/etc/nixos"
MANIFEST="${ROOT}/machines/q958/disko-deprecations.json"
VERIFY="${ROOT}/scripts/disko-verify-active.sh"
MODE="${1:-check}"

usage() {
  cat <<EOF
disko-prune-deprecated — Legacy-Code nach disko-Reinstall entfernen

Usage:
  disko-prune-deprecated.sh check     # Zeigt was entfernt würde (Default)
  disko-prune-deprecated.sh apply   # Entfernt Marker-Blöcke (nach verify)

Ablauf für KI/Mensch:
  1. disko-Reinstall + nixos-install
  2. profile.nix: storage.tierA.diskoManaged = true
  3. sudo nixos-rebuild-safe dry
  4. sudo ${VERIFY}
  5. sudo ${0} check
  6. sudo ${0} apply
  7. sudo nixos-rebuild-safe dry (erneut)

Marker-Format in .nix:
  # DEPRECATED-DISKO-START: <id>
  ...
  # DEPRECATED-DISKO-END: <id>
EOF
}

prune_file() {
  local file="$1" marker="$2" dry="$3"
  local path="${ROOT}/${file}"
  [[ -f "$path" ]] || { echo "SKIP fehlt: $file"; return 0; }

  if ! grep -q "DEPRECATED-DISKO-START: ${marker}" "$path"; then
    echo "SKIP kein Marker ${marker} in ${file}"
    return 0
  fi

  if [[ "$dry" == "1" ]]; then
    echo "WOULD REMOVE marker=${marker} file=${file}"
    sed -n "/DEPRECATED-DISKO-START: ${marker}/,/DEPRECATED-DISKO-END: ${marker}/p" "$path" | head -20
    echo "  ... ($(sed -n "/DEPRECATED-DISKO-START: ${marker}/,/DEPRECATED-DISKO-END: ${marker}/p" "$path" | wc -l) Zeilen)"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  awk -v m="$marker" '
    $0 ~ "DEPRECATED-DISKO-START: " m { skip=1; next }
    $0 ~ "DEPRECATED-DISKO-END: " m { skip=0; next }
    !skip { print }
  ' "$path" > "$tmp"
  cp "$tmp" "$path"
  rm -f "$tmp"
  echo "REMOVED marker=${marker} file=${file}"
}

run_prune() {
  local dry="$1"
  while IFS=$'\t' read -r file marker optional; do
    [[ "$optional" == "True" ]] && continue
    prune_file "$file" "$marker" "$dry"
  done < <(python3 -c "
import json
from pathlib import Path
m=json.loads(Path('/etc/nixos/machines/q958/disko-deprecations.json').read_text())
for d in m['deprecations']:
    if not d.get('optional'):
        print(d['file'], d['marker'], sep='\t')
")

  if [[ "$dry" == "1" ]]; then
    echo "=== check only — für apply: sudo $0 apply ==="
  else
    echo "=== apply done — jetzt: sudo nixos-rebuild-safe dry ==="
  fi
}

case "$MODE" in
  check)
    if [[ -x "$VERIFY" ]]; then
      if ! "$VERIFY"; then
        echo "ABBRUCH: verify fehlgeschlagen — prune nicht ausführen" >&2
        exit 1
      fi
    fi
    run_prune 1
    ;;
  apply)
    if ! "$VERIFY"; then
      echo "ABBRUCH: verify fehlgeschlagen" >&2
      exit 1
    fi
    echo "Entferne DEPRECATED-DISKO-Blöcke in 3s (Ctrl+C)…" >&2
    sleep 3
    run_prune 0
    ;;
  help | -h | --help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac