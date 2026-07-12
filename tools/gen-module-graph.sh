#!/usr/bin/env bash
# Generate filtered Mermaid module graphs from nixosConfigurations.q958.graph
# Usage: sudo bash /etc/nixos/tools/gen-module-graph.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Bitte mit sudo ausführen: sudo bash $0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/diagrams"
GRAPH="$(mktemp /tmp/q958-graph.XXXXXX.json)"
FILTERED="$(mktemp /tmp/q958-graph-filtered.XXXXXX.json)"
trap 'rm -f "$GRAPH" "$FILTERED"' EXIT

mkdir -p "$OUT"
cd "$ROOT"

nixoscope_cmd() {
  if command -v nixoscope >/dev/null 2>&1; then
    nixoscope "$@"
  else
    nix run nixpkgs#nixoscope -- "$@"
  fi
}

filter_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$ROOT/tools/filter-module-graph.py" "$1"
  else
    nix run nixpkgs#python3 -- "$ROOT/tools/filter-module-graph.py" "$1"
  fi
}

echo "Evaluating module graph..."
nix eval --json .#nixosConfigurations.q958.graph > "$GRAPH"

# name:path-prefix (empty prefix = repo-wide modules/lib/machines)
filters=(
  "modules-all:"
  "50-media:modules/50-media"
  "60-apps:modules/60-apps"
  "90-policy:modules/90-policy"
  "lib:lib"
)

for spec in "${filters[@]}"; do
  name="${spec%%:*}"
  prefix="${spec#*:}"
  echo "  → ${name}.mm (${prefix:-repo})"
  filter_cmd "$prefix" < "$GRAPH" > "$FILTERED"
  nixoscope_cmd --input "$FILTERED" --format mm > "$OUT/${name}.mm"
done

echo "OK: ${OUT}/*.mm"
