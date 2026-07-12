#!/usr/bin/env python3
"""Filter nixosConfigurations.*.graph JSON by repo-relative path prefix."""
from __future__ import annotations

import json
import re
import sys
from typing import Any

REPO_PREFIXES = ("modules/", "lib/", "machines/", "flake.nix", "users/")


def repo_rel(file: str) -> str | None:
    match = re.search(r"-source/(.+)$", file)
    return match.group(1) if match else None


def matches_prefix(rel: str | None, prefix: str) -> bool:
    if rel is None:
        return False
    if not prefix:
        return rel == "flake.nix" or rel.startswith(REPO_PREFIXES)
    return rel == prefix or rel.startswith(prefix + "/")


def imports_default_nix(node: dict[str, Any]) -> bool:
    for imp in node.get("imports", []):
        if repo_rel(imp.get("file", "")) == "machines/q958/default.nix":
            return True
        if imports_default_nix(imp):
            return True
    return False


def find_flake_entry(graph: list[dict[str, Any]]) -> dict[str, Any] | None:
    for entry in graph:
        if repo_rel(entry.get("file", "")) != "flake.nix":
            continue
        if imports_default_nix(entry):
            return entry
    return None


def prune(node: dict[str, Any], prefix: str) -> dict[str, Any] | None:
    pruned_imports: list[dict[str, Any]] = []
    for imp in node.get("imports", []):
        child = prune(imp, prefix)
        if child is not None:
            pruned_imports.append(child)

    rel = repo_rel(node.get("file", ""))
    keep_self = matches_prefix(rel, prefix)
    keep_chain = rel in {"flake.nix", "machines/q958/default.nix", "machines/q958/hardware.nix"}

    if keep_self or keep_chain or pruned_imports:
        return {**node, "imports": pruned_imports}
    return None


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-prefix>", file=sys.stderr)
        print("  empty prefix = all repo modules/lib/machines", file=sys.stderr)
        sys.exit(2)

    prefix = sys.argv[1]
    graph = json.load(sys.stdin)
    if not isinstance(graph, list):
        print("expected top-level JSON array", file=sys.stderr)
        sys.exit(1)

    entry = find_flake_entry(graph)
    if entry is None:
        print("q958 flake.nix entry not found in graph", file=sys.stderr)
        sys.exit(1)

    pruned = prune(entry, prefix)
    if pruned is None:
        print("no nodes matched prefix", file=sys.stderr)
        sys.exit(1)

    json.dump([pruned], sys.stdout)


if __name__ == "__main__":
    main()
