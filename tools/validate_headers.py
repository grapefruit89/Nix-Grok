#!/usr/bin/env python3
"""
validate_headers.py -- NIXMETA-Verbot, Header-Pflicht-Check.

NIXMETA (das alte "# !type"-Annotationsformat) ist seit 2026-06-26 absolut
verboten. Dieses Skript scannt jede .nix-Datei und schlaegt fehl, wenn
verbotene Marker gefunden werden. Wird als pre-commit Hook UND als Teil
der Nix-Assertion (modules/00-core.nix) genutzt.
"""
import sys
import re
from pathlib import Path

FORBIDDEN = re.compile(r"^\s*#\s*!(type|enum|list|id|range|bool|path|url)\b")
REPO_ROOT = Path(__file__).resolve().parent.parent

def scan(root: Path) -> list[tuple[Path, int, str]]:
    violations = []
    for f in root.rglob("*.nix"):
        if "/.git/" in str(f) or "/stage-nixos/" in str(f):
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if FORBIDDEN.match(line):
                violations.append((f, i, line.strip()))
    return violations

def main() -> int:
    violations = scan(REPO_ROOT)
    if violations:
        print("NIXMETA-VERSTOSS gefunden -- absolut verboten seit 2026-06-26:")
        for f, i, line in violations:
            print(f"  {f.relative_to(REPO_ROOT)}:{i}: {line}")
        print("\nNutze stattdessen den freien YAML-Header (siehe AGENTS.md / SERVICE_TEMPLATE.nix).")
        return 1
    print(f"OK -- keine NIXMETA-Marker in {REPO_ROOT}.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
