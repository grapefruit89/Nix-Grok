#!/usr/bin/env python3
"""
Build nixos_docs.sqlite: DuckDB-Migration + chat_insights + sqlite-vec.

Quelle DuckDB wird read-only gelesen. Ziel wird neu erzeugt (oder --backup).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import struct
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SEED = SCRIPT_DIR / "chat_insights_seed.json"
EMBED_DIM = 384  # nomic-embed-text / all-MiniLM-L6-v2 kompatibel


def migrate_duckdb_tables(source: Path, conn: sqlite3.Connection) -> None:
    import duckdb

    src = duckdb.connect(str(source), read_only=True)
    tables = [r[0] for r in src.execute("SHOW TABLES").fetchall()]
    for table in tables:
        columns = src.execute(f'DESCRIBE "{table}"').fetchall()
        col_defs = ", ".join(
            f'"{name}" TEXT' if "CHAR" in dtype.upper() or "TEXT" in dtype.upper()
            else f'"{name}" INTEGER'
            for name, dtype, *_ in columns
        )
        conn.execute(f'DROP TABLE IF EXISTS "{table}"')
        conn.execute(f'CREATE TABLE "{table}" ({col_defs})')
        rows = src.execute(f'SELECT * FROM "{table}"').fetchall()
        if rows:
            placeholders = ",".join("?" * len(columns))
            names = ", ".join(f'"{c[0]}"' for c in columns)
            conn.executemany(
                f'INSERT INTO "{table}" ({names}) VALUES ({placeholders})',
                rows,
            )
        print(f"migrated {table}: {len(rows)} rows")
    src.close()


def load_sqlite_vec(conn: sqlite3.Connection) -> None:
    vec_so = os.environ.get("SQLITE_VEC_PATH")
    if not vec_so:
        try:
            vec_so = subprocess.check_output(
                ["nix-build", "<nixpkgs>", "-A", "sqlite-vec", "--no-link", "--out-link", "/tmp/sqlite-vec-out"],
                text=True,
            ).strip() + "/lib/vec0.so"
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("WARN: sqlite-vec nicht geladen — Vektor-Suche deaktiviert", file=sys.stderr)
            return
    conn.enable_load_extension(True)
    conn.load_extension(vec_so)
    conn.enable_load_extension(False)
    print(f"sqlite-vec: {vec_so}")


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
        """
    )


def import_seed(conn: sqlite3.Connection, seed_path: Path) -> int:
    if not seed_path.is_file():
        print(f"Kein Seed: {seed_path}")
        return 0
    items = json.loads(seed_path.read_text())
    conn.execute("DELETE FROM chat_insights WHERE source_path LIKE 'neuesmaterialfuergrok%' OR source_path LIKE 'grok/%' OR source_path LIKE 'deepseek/%' OR source_path LIKE 'claude/%'")
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


def create_vec_tables(conn: sqlite3.Connection) -> None:
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
            CREATE VIRTUAL TABLE IF NOT EXISTS document_embeddings USING vec0(
              document_id INTEGER PRIMARY KEY,
              embedding float[{EMBED_DIM}]
            )
            """
        )
        print("vec0 tables: insight_embeddings, document_embeddings")
    except sqlite3.OperationalError as exc:
        print(f"WARN: vec0 nicht erstellt: {exc}", file=sys.stderr)


def zero_embedding() -> bytes:
    return struct.pack(f"{EMBED_DIM}f", *([0.0] * EMBED_DIM))


def embed_via_ollama(text: str, model: str, host: str) -> list[float] | None:
    import urllib.request

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
    except Exception as exc:
        print(f"WARN: Ollama embed fehlgeschlagen: {exc}", file=sys.stderr)
    return None


def pack_embedding(vec: list[float]) -> bytes:
    if len(vec) != EMBED_DIM:
        if len(vec) > EMBED_DIM:
            vec = vec[:EMBED_DIM]
        else:
            vec = vec + [0.0] * (EMBED_DIM - len(vec))
    return struct.pack(f"{EMBED_DIM}f", *vec)


def populate_embeddings(conn: sqlite3.Connection, ollama_host: str | None, ollama_model: str) -> None:
    try:
        conn.execute("SELECT 1 FROM insight_embeddings LIMIT 1")
    except sqlite3.OperationalError:
        return

    conn.execute("DELETE FROM insight_embeddings")
    rows = conn.execute("SELECT id, title, content FROM chat_insights").fetchall()
    for insight_id, title, content in rows:
        text = f"{title}\n{content}"
        vec = None
        if ollama_host:
            vec = embed_via_ollama(text, ollama_model, ollama_host)
        blob = pack_embedding(vec) if vec else zero_embedding()
        conn.execute(
            "INSERT INTO insight_embeddings (insight_id, embedding) VALUES (?, ?)",
            (insight_id, blob),
        )
    print(f"embeddings: {len(rows)} insights ({'ollama' if ollama_host else 'zero-placeholder'})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duckdb", type=Path, help="Read-only DuckDB source (nixos_docs.db)")
    parser.add_argument("--target", type=Path, default=Path("data/nixos_docs.sqlite"))
    parser.add_argument("--seed", type=Path, default=DEFAULT_SEED)
    parser.add_argument("--backup", action="store_true")
    parser.add_argument("--ollama-host", default=os.environ.get("OLLAMA_HOST"))
    parser.add_argument("--ollama-model", default=os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text"))
    args = parser.parse_args()

    if args.target.exists():
        if args.backup:
            bak = args.target.with_suffix(args.target.suffix + ".bak")
            shutil.copy2(args.target, bak)
            print(f"Backup: {bak}")
        args.target.unlink()

    args.target.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(args.target))

    try:
        if args.duckdb:
            migrate_duckdb_tables(args.duckdb, conn)
        create_insights_schema(conn)
        n = import_seed(conn, args.seed)
        print(f"chat_insights: {n} seed rows")
        load_sqlite_vec(conn)
        create_vec_tables(conn)
        populate_embeddings(conn, args.ollama_host, args.ollama_model)
        conn.commit()
        doc_count = conn.execute("SELECT count(*) FROM documents").fetchone()[0] if args.duckdb else 0
        insight_count = conn.execute("SELECT count(*) FROM chat_insights").fetchone()[0]
        print(f"OK -> {args.target} ({doc_count} docs, {insight_count} insights)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()