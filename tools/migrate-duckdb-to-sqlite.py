#!/usr/bin/env python3
"""Migrate nixos_docs.db (DuckDB) → nixos_docs.sqlite without modifying the source."""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("duckdb Python package required (nix-shell -p python3Packages.duckdb)", file=sys.stderr)
    sys.exit(1)

TABLES = ("documents", "document_tags", "bundles", "bundles_link")

SQLITE_TYPES = {
    "INTEGER": "INTEGER",
    "BIGINT": "INTEGER",
    "VARCHAR": "TEXT",
    "BOOLEAN": "INTEGER",
    "TIMESTAMP": "TEXT",
    "DATE": "TEXT",
    "DOUBLE": "REAL",
}


def duck_type_to_sqlite(duck_type: str) -> str:
    base = duck_type.upper().split("(")[0].strip()
    return SQLITE_TYPES.get(base, "TEXT")


def migrate(source: Path, target: Path, backup: bool) -> None:
    if not source.is_file():
        raise SystemExit(f"Source not found: {source}")

    if target.exists():
        if backup:
            backup_path = target.with_suffix(target.suffix + ".bak")
            shutil.copy2(target, backup_path)
            print(f"Backup: {backup_path}")
        target.unlink()

    src = duckdb.connect(str(source), read_only=True)
    tgt = sqlite3.connect(str(target))

    try:
        for table in TABLES:
            exists = src.execute(
                "SELECT count(*) FROM information_schema.tables WHERE table_name = ?",
                [table],
            ).fetchone()[0]
            if not exists:
                print(f"Skip missing table: {table}")
                continue

            columns = src.execute(f"DESCRIBE {table}").fetchall()
            col_defs = ", ".join(
                f'"{name}" {duck_type_to_sqlite(dtype)}' for name, dtype, *_ in columns
            )
            tgt.execute(f'DROP TABLE IF EXISTS "{table}"')
            tgt.execute(f'CREATE TABLE "{table}" ({col_defs})')

            rows = src.execute(f'SELECT * FROM "{table}"').fetchall()
            if rows:
                placeholders = ",".join("?" * len(columns))
                col_names = ", ".join(f'"{c[0]}"' for c in columns)
                tgt.executemany(
                    f'INSERT INTO "{table}" ({col_names}) VALUES ({placeholders})',
                    rows,
                )
            print(f"{table}: {len(rows)} rows")
        tgt.commit()
    finally:
        src.close()
        tgt.close()

    verify = sqlite3.connect(str(target))
    try:
        count = verify.execute("SELECT count(*) FROM documents").fetchone()[0]
        print(f"OK → {target} ({count} documents)")
    finally:
        verify.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Input DuckDB file (read-only)")
    parser.add_argument(
        "target",
        type=Path,
        nargs="?",
        default=Path("nixos_docs.sqlite"),
        help="Output SQLite file (default: nixos_docs.sqlite)",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="Backup existing target before overwrite",
    )
    args = parser.parse_args()
    migrate(args.source, args.target, args.backup)


if __name__ == "__main__":
    main()