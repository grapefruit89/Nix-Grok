"""Shared helpers for nixos_docs.sqlite indexing and chunking (FTS5 only)."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any


def extract_comment_meta_block(content: str, max_lines: int = 40) -> str | None:
    lines = content.split("\n")
    in_block = False
    buf: list[str] = []

    for line in lines[:max_lines]:
        stripped = line.strip()
        if stripped == "# ---":
            if not in_block:
                in_block = True
                continue
            break
        if in_block and line.startswith("#"):
            buf.append(line[1:])

    if not buf:
        return None
    return "\n".join(buf)


def extract_frontmatter_block(content: str, max_lines: int = 80) -> str | None:
    if not content.startswith("---"):
        return extract_comment_meta_block(content, max_lines=max_lines)

    lines = content.split("\n")
    buf: list[str] = []

    for line in lines[1:max_lines]:
        if line.strip() == "---":
            break
        buf.append(line)

    if not buf:
        return None
    return "\n".join(buf)


def _strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_yaml_subset(text: str) -> dict[str, Any]:
    """Parse the small YAML subset used in meta frontmatter."""
    root: dict[str, Any] = {}
    stack: list[tuple[int, dict[str, Any] | list[Any]]] = [(0, root)]
    pending_key: str | None = None

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue

        indent = len(raw) - len(raw.lstrip())
        line = raw.strip()

        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()

        container = stack[-1][1]
        assert isinstance(container, dict)

        if line.startswith("- "):
            item = _strip_quotes(line[2:].strip())
            if pending_key is None:
                continue
            target = container.get(pending_key)
            if isinstance(target, dict) and not target:
                target = []
                container[pending_key] = target
                stack.pop()
            elif not isinstance(target, list):
                target = []
                container[pending_key] = target
            target.append(item)
            continue

        if ":" not in line:
            continue

        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()
        pending_key = key

        if rest == "":
            child: dict[str, Any] = {}
            container[key] = child
            stack.append((indent, child))
            continue

        if rest.startswith("[") and rest.endswith("]"):
            inner = rest[1:-1].strip()
            if not inner:
                container[key] = []
            else:
                container[key] = [
                    _strip_quotes(part.strip()) for part in inner.split(",") if part.strip()
                ]
            continue

        container[key] = _strip_quotes(rest)

    return root


def normalize_meta(parsed: dict[str, Any]) -> dict[str, Any]:
    meta = parsed.get("meta")
    if isinstance(meta, dict):
        return meta
    return parsed


def extract_file_meta(content: str, *, is_nix: bool = False) -> dict[str, Any]:
    block = extract_comment_meta_block(content) if is_nix else extract_frontmatter_block(content)
    if not block:
        return {}
    parsed = parse_yaml_subset(block)
    return normalize_meta(parsed)


def meta_list(meta: dict[str, Any], key: str) -> list[str]:
    value = meta.get(key)
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    if isinstance(value, str):
        return [value]
    return []


def strip_frontmatter(content: str) -> str:
    if not content.startswith("---"):
        return content
    lines = content.split("\n")
    for idx, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "\n".join(lines[idx + 1 :])
    return content


HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)(?:\s+\{#([^}]+)\})?\s*$", re.MULTILINE)
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")


def chunk_markdown(content: str) -> list[dict[str, Any]]:
    body = strip_frontmatter(content)
    matches = list(HEADING_RE.finditer(body))
    if not matches:
        text = body.strip()
        if not text:
            return []
        return [
            {
                "heading": "",
                "anchor": "",
                "level": 0,
                "content": text,
                "chunk_index": 0,
            }
        ]

    chunks: list[dict[str, Any]] = []
    preamble = body[: matches[0].start()].strip()
    if preamble:
        chunks.append(
            {
                "heading": "",
                "anchor": "",
                "level": 0,
                "content": preamble,
                "chunk_index": 0,
            }
        )

    for idx, match in enumerate(matches):
        level = len(match.group(1))
        if level > 3:
            continue
        heading = match.group(2).strip()
        anchor = (match.group(3) or "").strip()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(body)
        section = body[start:end].strip()
        chunk_body = f"{heading}\n\n{section}".strip() if section else heading
        chunks.append(
            {
                "heading": heading,
                "anchor": anchor,
                "level": level,
                "content": chunk_body,
                "chunk_index": len(chunks),
            }
        )

    return chunks


def extract_siehe_auch_links(content: str) -> list[tuple[str, str]]:
    body = strip_frontmatter(content)
    section_match = re.search(
        r"^##\s+Siehe auch.*$([\s\S]*?)(?=^##\s+|\Z)",
        body,
        flags=re.MULTILINE | re.IGNORECASE,
    )
    if not section_match:
        return []

    links: list[tuple[str, str]] = []
    for _text, target in LINK_RE.findall(section_match.group(1)):
        path_part = target.split("#", 1)[0].strip()
        anchor = ""
        if "#" in target:
            anchor = target.split("#", 1)[1].strip()
        if not path_part:
            continue
        links.append((path_part, anchor))
    return links


def resolve_doc_path(from_path: str, target: str) -> str:
    target = target.strip()
    if target.startswith("/"):
        return target.lstrip("/")
    base = Path(from_path).parent
    return str((base / target).as_posix()).replace("/./", "/")