#!/usr/bin/env bash
# Installiert pre-push Hook → tools/verify-no-secrets.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-push"

if [[ ! -d "$ROOT/.git" ]]; then
  echo "Kein Git-Repo unter $ROOT"
  exit 1
fi

cat > "$HOOK" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$ROOT/tools/verify-no-secrets.sh"
EOF
chmod +x "$HOOK"
echo "OK: pre-push → tools/verify-no-secrets.sh"