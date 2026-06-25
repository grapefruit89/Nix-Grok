#!/usr/bin/env bash
# Pre-commit / pre-push: keine Secrets im Index
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -E 'passwordHash\s*=\s*"\$[a-zA-Z0-9]|q958-dev-|privateKey\s*=\s*"[A-Za-z0-9+/]{40,}="' \
    -- ':!*.example' ':!docs/SECURITY.md' ':!docs/SESSION-*.md' ':!tools/verify-no-secrets.sh' ':!claudereview_prompt.md' 2>/dev/null; then
    echo "FAIL: Secrets in getrackten Dateien gefunden"
    FAIL=1
  fi
fi

for f in machines/q958/profile.local.nix secrets.sops.yaml; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "FAIL: $f ist getrackt (sollte gitignored sein)"
    FAIL=1
  fi
done

if [ "$FAIL" -eq 0 ]; then
  echo "OK: keine Secrets im Git-Index"
fi
exit "$FAIL"