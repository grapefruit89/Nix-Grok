#!/usr/bin/env python3
"""
Import chat_insights seed into nixos_docs.sqlite (FTS5 only — keine Embeddings).

q958: Keine lokale KI — siehe docs/guides/ANTIPATTERNS.md#lokale-ki

Usage:
  python3 build_nixos_knowledge_db.py --target /var/lib/nixos-docs-mcp/nixos_docs.sqlite
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED)
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--fresh", action="store_true", help="DB löschen und neu anlegen")
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
        n = import_seed(conn, args.seed)
        print(f"chat_insights seed: {n} rows")

        try:
            conn.execute("INSERT INTO chat_insights_fts(chat_insights_fts) VALUES('optimize')")
        except sqlite3.OperationalError:
            pass

        conn.commit()
        insights = conn.execute("SELECT count(*) FROM chat_insights").fetchone()[0]
        print(f"OK → {args.target} ({insights} insights, FTS5)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()