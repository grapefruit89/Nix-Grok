"""Shared helpers for nixos_docs.sqlite indexing, chunking, and embeddings."""

from __future__ import annotations

import json
import os
import re
import struct
import subprocess
import urllib.request
from pathlib import Path
from typing import Any

EMBED_DIM = 384


def find_vec_so() -> str | None:
    import glob

    hits = sorted(glob.glob("/nix/store/*/lib/vec0.so"))
    return hits[-1] if hits else None


def load_sqlite_vec(conn, vec_so: str | None = None) -> str | None:
    vec_so = vec_so or os.environ.get("SQLITE_VEC_PATH")
    if not vec_so:
        try:
            vec_so = (
                subprocess.check_output(
                    [
                        "nix-build",
                        "<nixpkgs>",
                        "-A",
                        "sqlite-vec",
                        "--no-link",
                        "--out-link",
                        "/tmp/sqlite-vec-out",
                    ],
                    text=True,
                ).strip()
                + "/lib/vec0.so"
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
    conn.enable_load_extension(True)
    conn.load_extension(vec_so)
    conn.enable_load_extension(False)
    return vec_so


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


def zero_embedding() -> bytes:
    return struct.pack(f"{EMBED_DIM}f", *([0.0] * EMBED_DIM))


def pack_embedding(vec: list[float]) -> bytes:
    if len(vec) != EMBED_DIM:
        if len(vec) > EMBED_DIM:
            vec = vec[:EMBED_DIM]
        else:
            vec = vec + [0.0] * (EMBED_DIM - len(vec))
    return struct.pack(f"{EMBED_DIM}f", *vec)


def embed_via_ollama(text: str, model: str, host: str) -> list[float] | None:
    payload = json.dumps({"model": model, "input": text}).encode()
    req = urllib.request.Request(
        f"{host.rstrip('/')}/api/embed",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.load(resp)
        embeddings = data.get("embeddings") or data.get("embedding")
        if isinstance(embeddings, list) and embeddings and isinstance(embeddings[0], list):
            return embeddings[0]
        if isinstance(embeddings, list) and embeddings and isinstance(embeddings[0], (int, float)):
            return embeddings
    except Exception:
        return None
    return None
