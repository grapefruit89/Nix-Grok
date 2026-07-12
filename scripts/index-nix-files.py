#!/usr/bin/env python3
# ---
# meta:
#   role: script
#   purpose: Indexiert .nix + .md + .sh in nixos_docs.sqlite (source_files, doc_meta, doc_chunks, doc_links)
#   tags:
#     - mcp
#     - sqlite
#     - indexer
# ---
"""
Indexiert alle .nix, .md und .sh Dateien aus /etc/nixos in nixos_docs.sqlite.

Tabellen:
  source_files + source_files_fts  — Volltext (.nix/.md/.sh)
  doc_meta / doc_tags              — strukturiertes Frontmatter
  doc_chunks + doc_chunks_fts      — Markdown-Abschnitte (##/###)
  doc_links                        — meta.docs, betrifft, ## Siehe auch

Usage:
  python3 index-nix-files.py [--db PATH] [--root PATH] [--dry-run]
"""
import argparse
import hashlib
import json
import re
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from knowledge_db_common import (
    chunk_markdown,
    extract_file_meta,
    extract_siehe_auch_links,
    meta_list,
    resolve_doc_path,
)

DB_PATH = "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"
NIXOS_ROOT = "/etc/nixos"

EXCLUDE_DIRS = {
    ".git", "secrets", ".local", ".ssh",
    "result", ".direnv", ".npm", ".grok",
    "node_modules",
}
EXCLUDE_FILES = {
    "flake.lock", "secrets.yaml", "infra.yaml", "media.yaml",
}

INCLUDE_EXTENSIONS = {".nix", ".md", ".sh"}

KIND_MAP = {
    ".nix": "nix",
    ".md": "md",
    ".sh": "sh",
}


def relative_path(abs_path: str, root: str) -> str:
    return abs_path[len(root):].lstrip("/")


def should_exclude(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    for part in rel.parts[:-1]:
        if part in EXCLUDE_DIRS:
            return True
    if path.name in EXCLUDE_FILES:
        return True
    return False


def iter_files(root: str):
    root_path = Path(root)
    for ext in INCLUDE_EXTENSIONS:
        for p in root_path.rglob(f"*{ext}"):
            if not p.is_file():
                continue
            if should_exclude(p, root_path):
                continue
            yield p


def infer_module_role(rel_path: str, meta: dict) -> str:
    if meta.get("role"):
        return str(meta["role"])
    if rel_path.startswith("docs/adr/"):
        return "adr"
    if rel_path.startswith("docs/guides/"):
        return "guide"
    if rel_path.startswith("docs/learnings/"):
        return "learning"
    if rel_path.startswith("docs/"):
        return "doc"
    if rel_path.startswith("lib/"):
        return "lib"
    if rel_path.startswith("modules/"):
        return "module"
    if rel_path.startswith("machines/"):
        return "machine"
    if rel_path.startswith("scripts/"):
        return "script"
    if rel_path.startswith("packages/"):
        return "package"
    if rel_path.startswith("stage-nixos/modules/"):
        return "module"
    if rel_path.startswith("stage-nixos/users/"):
        return "user"
    if rel_path.startswith("stage-nixos/"):
        return "machine"
    if rel_path.startswith("tools/"):
        return "tool"
    if rel_path.startswith("mcp/"):
        return "mcp"
    return "other"


def ensure_schema(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS source_files (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            path        TEXT NOT NULL UNIQUE,
            kind        TEXT NOT NULL,
            layer       INTEGER,
            module_role TEXT,
            purpose     TEXT,
            content     TEXT NOT NULL,
            size_bytes  INTEGER,
            mtime       REAL,
            indexed_at  REAL DEFAULT (unixepoch())
        );

        CREATE INDEX IF NOT EXISTS idx_sf_kind  ON source_files(kind);
        CREATE INDEX IF NOT EXISTS idx_sf_role  ON source_files(module_role);
        CREATE INDEX IF NOT EXISTS idx_sf_layer ON source_files(layer);

        CREATE VIRTUAL TABLE IF NOT EXISTS source_files_fts USING fts5(
            path, kind, module_role, purpose, content,
            content='source_files', content_rowid='id',
            tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS sf_fts_insert AFTER INSERT ON source_files BEGIN
            INSERT INTO source_files_fts(rowid, path, kind, module_role, purpose, content)
            VALUES (new.id, new.path, new.kind, new.module_role, new.purpose, new.content);
        END;
        CREATE TRIGGER IF NOT EXISTS sf_fts_delete AFTER DELETE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, path, kind, module_role, purpose, content)
            VALUES ('delete', old.id, old.path, old.kind, old.module_role, old.purpose, old.content);
        END;
        CREATE TRIGGER IF NOT EXISTS sf_fts_update AFTER UPDATE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, path, kind, module_role, purpose, content)
            VALUES ('delete', old.id, old.path, old.kind, old.module_role, old.purpose, old.content);
            INSERT INTO source_files_fts(rowid, path, kind, module_role, purpose, content)
            VALUES (new.id, new.path, new.kind, new.module_role, new.purpose, new.content);
        END;

        CREATE TABLE IF NOT EXISTS doc_meta (
            source_file_id INTEGER PRIMARY KEY REFERENCES source_files(id) ON DELETE CASCADE,
            path           TEXT NOT NULL UNIQUE,
            role           TEXT,
            status         TEXT,
            doc_date       TEXT,
            purpose        TEXT,
            error_pattern  TEXT,
            quick_fix      TEXT,
            meta_json      TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_doc_meta_status ON doc_meta(status);
        CREATE INDEX IF NOT EXISTS idx_doc_meta_role   ON doc_meta(role);

        CREATE TABLE IF NOT EXISTS doc_tags (
            source_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            tag            TEXT NOT NULL,
            PRIMARY KEY (source_file_id, tag)
        );
        CREATE INDEX IF NOT EXISTS idx_doc_tags_tag ON doc_tags(tag);

        CREATE TABLE IF NOT EXISTS doc_chunks (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            source_file_id INTEGER NOT NULL REFERENCES source_files(id) ON DELETE CASCADE,
            path           TEXT NOT NULL,
            heading        TEXT,
            anchor         TEXT,
            level          INTEGER,
            content        TEXT NOT NULL,
            chunk_index    INTEGER NOT NULL,
            content_hash   TEXT,
            UNIQUE(source_file_id, chunk_index)
        );
        CREATE INDEX IF NOT EXISTS idx_doc_chunks_path ON doc_chunks(path);

        CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunks_fts USING fts5(
            path, heading, anchor, content,
            content='doc_chunks', content_rowid='id',
            tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS dc_fts_insert AFTER INSERT ON doc_chunks BEGIN
            INSERT INTO doc_chunks_fts(rowid, path, heading, anchor, content)
            VALUES (new.id, new.path, new.heading, new.anchor, new.content);
        END;
        CREATE TRIGGER IF NOT EXISTS dc_fts_delete AFTER DELETE ON doc_chunks BEGIN
            INSERT INTO doc_chunks_fts(doc_chunks_fts, rowid, path, heading, anchor, content)
            VALUES ('delete', old.id, old.path, old.heading, old.anchor, old.content);
        END;
        CREATE TRIGGER IF NOT EXISTS dc_fts_update AFTER UPDATE ON doc_chunks BEGIN
            INSERT INTO doc_chunks_fts(doc_chunks_fts, rowid, path, heading, anchor, content)
            VALUES ('delete', old.id, old.path, old.heading, old.anchor, old.content);
            INSERT INTO doc_chunks_fts(rowid, path, heading, anchor, content)
            VALUES (new.id, new.path, new.heading, new.anchor, new.content);
        END;

        CREATE TABLE IF NOT EXISTS doc_links (
            from_path TEXT NOT NULL,
            to_path   TEXT NOT NULL,
            link_type TEXT NOT NULL,
            anchor    TEXT,
            PRIMARY KEY (from_path, to_path, link_type)
        );
        CREATE INDEX IF NOT EXISTS idx_doc_links_to ON doc_links(to_path);
    """)
    conn.commit()


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def upsert_doc_meta(conn, file_id: int, rel: str, meta: dict):
    conn.execute("DELETE FROM doc_tags WHERE source_file_id = ?", (file_id,))
    conn.execute(
        """
        INSERT INTO doc_meta (
            source_file_id, path, role, status, doc_date, purpose,
            error_pattern, quick_fix, meta_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_file_id) DO UPDATE SET
            path = excluded.path,
            role = excluded.role,
            status = excluded.status,
            doc_date = excluded.doc_date,
            purpose = excluded.purpose,
            error_pattern = excluded.error_pattern,
            quick_fix = excluded.quick_fix,
            meta_json = excluded.meta_json
        """,
        (
            file_id,
            rel,
            meta.get("role"),
            meta.get("status"),
            meta.get("date"),
            meta.get("purpose"),
            meta.get("error_pattern"),
            meta.get("quick_fix"),
            json.dumps(meta, ensure_ascii=False),
        ),
    )
    for tag in meta_list(meta, "tags"):
        conn.execute(
            "INSERT OR IGNORE INTO doc_tags (source_file_id, tag) VALUES (?, ?)",
            (file_id, tag),
        )


def upsert_doc_chunks(conn, file_id: int, rel: str, md_content: str):
    conn.execute("DELETE FROM doc_chunks WHERE source_file_id = ?", (file_id,))
    for chunk in chunk_markdown(md_content):
        body = chunk["content"]
        conn.execute(
            """
            INSERT INTO doc_chunks (
                source_file_id, path, heading, anchor, level,
                content, chunk_index, content_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                file_id,
                rel,
                chunk["heading"],
                chunk["anchor"],
                chunk["level"],
                body,
                chunk["chunk_index"],
                content_hash(body),
            ),
        )


def upsert_doc_links(conn, rel: str, kind: str, meta: dict, md_content: str | None):
    conn.execute("DELETE FROM doc_links WHERE from_path = ?", (rel,))

    def add_link(target: str, link_type: str, anchor: str = ""):
        resolved = resolve_doc_path(rel, target)
        conn.execute(
            """
            INSERT OR IGNORE INTO doc_links (from_path, to_path, link_type, anchor)
            VALUES (?, ?, ?, ?)
            """,
            (rel, resolved, link_type, anchor),
        )

    for doc in meta_list(meta, "docs"):
        add_link(doc, "meta.docs")
    for path in meta_list(meta, "betrifft"):
        add_link(path, "betrifft")
    for lib in meta_list(meta, "lib"):
        add_link(lib, "meta.lib")

    if kind == "md" and md_content:
        for target, anchor in extract_siehe_auch_links(md_content):
            add_link(target, "siehe_auch", anchor)


def _normalize_module_path(raw: str) -> str | None:
    raw = raw.strip().strip("`")
    if not raw:
        return None
    if raw == "flake.nix":
        return raw
    if raw.startswith(("modules/", "lib/", "machines/", "scripts/", "tools/", "packages/")):
        return raw
    return None


def index_module_graph(conn, root: str, dry_run: bool = False) -> int:
    """Import-Kanten aus docs/diagrams/*.mm (NixoScope) → doc_links link_type=module_import."""
    diagrams = Path(root) / "docs" / "diagrams"
    if not diagrams.is_dir():
        return 0

    node_paths: dict[str, str] = {}
    edges: list[tuple[str, str]] = []

    node_re = re.compile(r'^\s+(\w+)\["`\*\*(.+?)\*\*', re.MULTILINE)
    edge_re = re.compile(r"^\s+(\w+)\s+-->\s+(\w+)\s*$", re.MULTILINE)

    for mm_file in sorted(diagrams.glob("*.mm")):
        try:
            content = mm_file.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"  SKIP {mm_file}: {e}", file=sys.stderr)
            continue

        local_nodes: dict[str, str] = {}
        for node_id, label in node_re.findall(content):
            path = _normalize_module_path(label.split("\n", 1)[0])
            if path:
                local_nodes[node_id] = path
                node_paths[node_id] = path

        for src_id, dst_id in edge_re.findall(content):
            src = local_nodes.get(src_id) or node_paths.get(src_id)
            dst = local_nodes.get(dst_id) or node_paths.get(dst_id)
            if src and dst:
                edges.append((src, dst))

    if dry_run:
        print(f"  DRY module_import: {len(edges)} Kanten aus {diagrams}")
        return len(edges)

    conn.execute("DELETE FROM doc_links WHERE link_type = 'module_import'")
    count = 0
    for src, dst in edges:
        conn.execute(
            """
            INSERT OR IGNORE INTO doc_links (from_path, to_path, link_type, anchor)
            VALUES (?, ?, 'module_import', '')
            """,
            (src, dst),
        )
        count += 1
    return count


def index_file(conn, path: Path, root: str, dry_run: bool = False) -> bool:
    rel = relative_path(str(path), root)
    kind = KIND_MAP.get(path.suffix, "other")

    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  SKIP {rel}: {e}", file=sys.stderr)
        return False

    meta = extract_file_meta(content, is_nix=(kind == "nix"))

    layer = None
    raw_layer = meta.get("layer")
    if raw_layer is not None and str(raw_layer).isdigit():
        layer = int(raw_layer)

    module_role = infer_module_role(rel, meta)
    purpose = str(meta.get("purpose") or "")
    size = len(content.encode("utf-8"))
    mtime = path.stat().st_mtime

    if dry_run:
        print(f"  DRY {kind:4} [{layer or '-'}] {module_role:10} {purpose[:40]:40} {rel}")
        return True

    conn.execute(
        """
        INSERT INTO source_files (path, kind, layer, module_role, purpose, content, size_bytes, mtime, indexed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, unixepoch())
        ON CONFLICT(path) DO UPDATE SET
            kind = excluded.kind, layer = excluded.layer,
            module_role = excluded.module_role, purpose = excluded.purpose,
            content = excluded.content, size_bytes = excluded.size_bytes,
            mtime = excluded.mtime, indexed_at = unixepoch()
        """,
        (rel, kind, layer, module_role, purpose, content, size, mtime),
    )
    file_id = conn.execute("SELECT id FROM source_files WHERE path = ?", (rel,)).fetchone()[0]

    if meta:
        upsert_doc_meta(conn, file_id, rel, meta)
        upsert_doc_links(conn, rel, kind, meta, content if kind == "md" else None)

    if kind == "md":
        upsert_doc_chunks(conn, file_id, rel, content)

    return True


def main():
    parser = argparse.ArgumentParser(description="Indexiert /etc/nixos in nixos_docs.sqlite")
    parser.add_argument("--db", default=DB_PATH)
    parser.add_argument("--root", default=NIXOS_ROOT)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    print(f"Indexer: {args.root} → {args.db}")
    if args.dry_run:
        print("DRY-RUN — keine Änderungen an der DB")

    conn = sqlite3.connect(args.db)
    ensure_schema(conn)

    total = ok = 0
    t0 = time.time()

    for path in iter_files(args.root):
        total += 1
        if index_file(conn, path, args.root, dry_run=args.dry_run):
            ok += 1

    graph_edges = index_module_graph(conn, args.root, dry_run=args.dry_run)

    if not args.dry_run:
        conn.commit()

        indexed_paths = {relative_path(str(p), args.root) for p in iter_files(args.root)}
        stale = {row[0] for row in conn.execute("SELECT path FROM source_files")} - indexed_paths
        if stale:
            conn.executemany("DELETE FROM source_files WHERE path = ?", [(p,) for p in stale])
            conn.commit()
            print(f"Stale Einträge entfernt: {len(stale)}")

        conn.execute("INSERT INTO source_files_fts(source_files_fts) VALUES('optimize')")
        try:
            conn.execute("INSERT INTO doc_chunks_fts(doc_chunks_fts) VALUES('optimize')")
        except sqlite3.OperationalError:
            pass
        conn.commit()

        sf = conn.execute("SELECT COUNT(*) FROM source_files").fetchone()[0]
        dm = conn.execute("SELECT COUNT(*) FROM doc_meta").fetchone()[0]
        dc = conn.execute("SELECT COUNT(*) FROM doc_chunks").fetchone()[0]
        dl = conn.execute("SELECT COUNT(*) FROM doc_links").fetchone()[0]
        md_purpose = conn.execute(
            "SELECT COUNT(*) FROM source_files WHERE kind='md' AND purpose IS NOT NULL AND purpose != ''"
        ).fetchone()[0]
        print(f"\nFertig: {ok}/{total} Dateien in {time.time()-t0:.1f}s")
        print(
            f"source_files={sf} doc_meta={dm} doc_chunks={dc} doc_links={dl} "
            f"module_import={graph_edges} md_with_purpose={md_purpose}"
        )
    else:
        print(f"\nDRY-RUN: {ok}/{total} Dateien würden indexiert")

    conn.close()


if __name__ == "__main__":
    main()