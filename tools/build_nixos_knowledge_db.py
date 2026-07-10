#!/usr/bin/env python3
"""
Build/augment nixos_docs.sqlite — serverless SQLite only (no DuckDB).

- chat_insights + chat_insights_fts (FTS5)
- insight_embeddings (sqlite-vec)
- doc_chunk_embeddings (sqlite-vec) — semantic search over Markdown chunks

Run after index-nix-files.py. Does NOT wipe the DB unless --fresh.

Usage:
  python3 build_nixos_knowledge_db.py --target /var/lib/nixos-docs-mcp/nixos_docs.sqlite
  python3 build_nixos_knowledge_db.py --target ... --ollama-host http://127.0.0.1:11434
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_SCRIPTS = SCRIPT_DIR.parent / "scripts"
sys.path.insert(0, str(REPO_SCRIPTS))

from knowledge_db_common import (  # noqa: E402
    EMBED_DIM,
    embed_via_ollama,
    load_sqlite_vec,
    pack_embedding,
    zero_embedding,
)

DEFAULT_SEED = SCRIPT_DIR / "chat_insights_seed.json"
DEFAULT_TARGET = Path("/var/lib/nixos-docs-mcp/nixos_docs.sqlite")


def create_insights_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS chat_insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          theme TEXT NOT NULL,
          agent TEXT NOT NULL,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          status TEXT DEFAULT 'proposed',
          rollout_stufe INTEGER,
          consensus TEXT,
          source_path TEXT,
          created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_insights_theme ON chat_insights(theme);
        CREATE INDEX IF NOT EXISTS idx_insights_agent ON chat_insights(agent);
        CREATE INDEX IF NOT EXISTS idx_insights_status ON chat_insights(status);

        CREATE VIRTUAL TABLE IF NOT EXISTS chat_insights_fts USING fts5(
          title, content, theme, agent, status,
          content='chat_insights', content_rowid='id',
          tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS ci_fts_insert AFTER INSERT ON chat_insights BEGIN
          INSERT INTO chat_insights_fts(rowid, title, content, theme, agent, status)
          VALUES (new.id, new.title, new.content, new.theme, new.agent, new.status);
        END;
        CREATE TRIGGER IF NOT EXISTS ci_fts_delete AFTER DELETE ON chat_insights BEGIN
          INSERT INTO chat_insights_fts(chat_insights_fts, rowid, title, content, theme, agent, status)
          VALUES ('delete', old.id, old.title, old.content, old.theme, old.agent, old.status);
        END;
        CREATE TRIGGER IF NOT EXISTS ci_fts_update AFTER UPDATE ON chat_insights BEGIN
          INSERT INTO chat_insights_fts(chat_insights_fts, rowid, title, content, theme, agent, status)
          VALUES ('delete', old.id, old.title, old.content, old.theme, old.agent, old.status);
          INSERT INTO chat_insights_fts(rowid, title, content, theme, agent, status)
          VALUES (new.id, new.title, new.content, new.theme, new.agent, new.status);
        END;
        """
    )


def import_seed(conn: sqlite3.Connection, seed_path: Path) -> int:
    if not seed_path.is_file():
        print(f"Kein Seed: {seed_path}")
        return 0
    items = json.loads(seed_path.read_text())
    conn.execute(
        "DELETE FROM chat_insights WHERE source_path LIKE 'neuesmaterialfuergrok%' "
        "OR source_path LIKE 'grok/%' OR source_path LIKE 'deepseek/%' "
        "OR source_path LIKE 'claude/%'"
    )
    count = 0
    for item in items:
        conn.execute(
            """
            INSERT INTO chat_insights (theme, agent, title, content, status, rollout_stufe, consensus, source_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                item["theme"],
                item["agent"],
                item["title"],
                item["content"],
                item.get("status", "proposed"),
                item.get("rollout_stufe"),
                item.get("consensus"),
                item.get("source_path", ""),
            ),
        )
        count += 1
    return count


def create_vec_tables(conn: sqlite3.Connection) -> bool:
    try:
        conn.execute(
            f"""
            CREATE VIRTUAL TABLE IF NOT EXISTS insight_embeddings USING vec0(
              insight_id INTEGER PRIMARY KEY,
              embedding float[{EMBED_DIM}]
            )
            """
        )
        conn.execute(
            f"""
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunk_embeddings USING vec0(
              chunk_id INTEGER PRIMARY KEY,
              embedding float[{EMBED_DIM}]
            )
            """
        )
        print("vec0 tables: insight_embeddings, doc_chunk_embeddings")
        return True
    except sqlite3.OperationalError as exc:
        print(f"WARN: vec0 nicht erstellt: {exc}", file=sys.stderr)
        return False


def populate_insight_embeddings(conn: sqlite3.Connection, ollama_host: str | None, ollama_model: str) -> int:
    try:
        conn.execute("SELECT 1 FROM insight_embeddings LIMIT 1")
    except sqlite3.OperationalError:
        return 0

    conn.execute("DELETE FROM insight_embeddings")
    rows = conn.execute("SELECT id, title, content FROM chat_insights").fetchall()
    for insight_id, title, content in rows:
        text = f"{title}\n{content}"
        vec = embed_via_ollama(text, ollama_model, ollama_host) if ollama_host else None
        blob = pack_embedding(vec) if vec else zero_embedding()
        conn.execute(
            "INSERT INTO insight_embeddings (insight_id, embedding) VALUES (?, ?)",
            (insight_id, blob),
        )
    print(f"insight_embeddings: {len(rows)} ({'ollama' if ollama_host else 'zero-placeholder'})")
    return len(rows)


def populate_doc_chunk_embeddings(
    conn: sqlite3.Connection, ollama_host: str | None, ollama_model: str, *, incremental: bool = True
) -> int:
    try:
        conn.execute("SELECT 1 FROM doc_chunk_embeddings LIMIT 1")
    except sqlite3.OperationalError:
        return 0

    rows = conn.execute(
        """
        SELECT c.id, c.path, c.heading, c.content, c.content_hash
        FROM doc_chunks c
        JOIN source_files sf ON sf.id = c.source_file_id
        WHERE sf.kind = 'md'
        ORDER BY c.id
        """
    ).fetchall()

    if incremental:
        existing = {
            row[0]: row[1]
            for row in conn.execute(
                """
                SELECT e.chunk_id, c.content_hash
                FROM doc_chunk_embeddings e
                JOIN doc_chunks c ON c.id = e.chunk_id
                """
            ).fetchall()
        }
    else:
        conn.execute("DELETE FROM doc_chunk_embeddings")
        existing = {}

    embedded = 0
    for chunk_id, path, heading, content, chash in rows:
        if incremental and existing.get(chunk_id) == chash:
            continue
        if chunk_id in existing:
            conn.execute("DELETE FROM doc_chunk_embeddings WHERE chunk_id = ?", (chunk_id,))

        text = f"{path}\n{heading}\n{content}" if heading else f"{path}\n{content}"
        vec = embed_via_ollama(text, ollama_model, ollama_host) if ollama_host else None
        blob = pack_embedding(vec) if vec else zero_embedding()
        conn.execute(
            "INSERT INTO doc_chunk_embeddings (chunk_id, embedding) VALUES (?, ?)",
            (chunk_id, blob),
        )
        embedded += 1

    print(f"doc_chunk_embeddings: {embedded} neu/aktualisiert, {len(rows)} chunks gesamt")
    return embedded


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED)
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--fresh", action="store_true", help="DB löschen und neu anlegen (nur für leere Tests)")
    parser.add_argument("--skip-seed", action="store_true")
    parser.add_argument("--insights-only", action="store_true")
    parser.add_argument("--docs-only", action="store_true")
    parser.add_argument("--full-reembed", action="store_true", help="Alle Chunk-Embeddings neu berechnen")
    parser.add_argument("--ollama-host", default=os.environ.get("OLLAMA_HOST"))
    parser.add_argument("--ollama-model", default=os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text"))
    args = parser.parse_args()

    if args.fresh and args.target.exists():
        if args.backup:
            bak = args.target.with_suffix(args.target.suffix + ".bak")
            shutil.copy2(args.target, bak)
            print(f"Backup: {bak}")
        args.target.unlink()

    args.target.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(args.target))

    try:
        create_insights_schema(conn)

        if not args.skip_seed and not args.docs_only:
            n = import_seed(conn, args.seed)
            print(f"chat_insights seed: {n} rows")

        vec_ok = load_sqlite_vec(conn) is not None
        if vec_ok:
            create_vec_tables(conn)

        if not args.docs_only:
            populate_insight_embeddings(conn, args.ollama_host, args.ollama_model)

        if not args.insights_only:
            populate_doc_chunk_embeddings(
                conn,
                args.ollama_host,
                args.ollama_model,
                incremental=not args.full_reembed,
            )

        try:
            conn.execute("INSERT INTO chat_insights_fts(chat_insights_fts) VALUES('optimize')")
        except sqlite3.OperationalError:
            pass

        conn.commit()

        chunks = conn.execute("SELECT count(*) FROM doc_chunks").fetchone()[0]
        insights = conn.execute("SELECT count(*) FROM chat_insights").fetchone()[0]
        print(f"OK → {args.target} ({insights} insights, {chunks} doc_chunks)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()