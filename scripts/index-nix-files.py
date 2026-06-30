#!/usr/bin/env python3
# ---
# meta:
#   role: script
#   purpose: Indexiert .nix + .md + .sh Dateien aus /etc/nixos in nixos_docs.sqlite (source_files)
#   tags:
#     - mcp
#     - sqlite
#     - indexer
# ---
"""
Indexiert alle .nix, .md und .sh Dateien aus /etc/nixos in die source_files Tabelle
von nixos_docs.sqlite. Kann als systemd-Service oder manuell ausgeführt werden.

Usage:
  python3 index-nix-files.py [--db PATH] [--root PATH] [--dry-run]
"""
import sys
import os
import re
import sqlite3
import argparse
import time
from pathlib import Path

DB_PATH   = "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"
NIXOS_ROOT = "/etc/nixos"

# Pfade die nicht indexiert werden (relativ zu NIXOS_ROOT)
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
    ".md":  "md",
    ".sh":  "sh",
}


def extract_nix_meta(content: str) -> dict:
    """Extrahiert meta-Block aus NixOS-Modul-Kommentaren.

    Erwartet Format:
    # ---
    # meta:
    #   layer: 3
    #   role: module
    #   purpose: ...
    # ---
    """
    meta = {}
    lines = content.split("\n")
    in_meta = False
    meta_lines = []

    for line in lines[:30]:  # nur ersten 30 Zeilen scannen
        stripped = line.strip()
        if stripped == "# ---":
            if not in_meta:
                in_meta = True
                continue
            else:
                break
        if in_meta and stripped.startswith("#"):
            meta_lines.append(stripped[1:].lstrip())

    for line in meta_lines:
        if line.startswith("meta:") or not line or line.startswith("-"):
            continue
        if ":" in line and not line.startswith(" "):
            key, _, val = line.partition(":")
            meta[key.strip()] = val.strip()

    return meta


def extract_md_frontmatter(content: str) -> dict:
    """Extrahiert YAML-Frontmatter aus Markdown-Dateien."""
    meta = {}
    if not content.startswith("---"):
        # Versuche auch Kommentar-basierte Meta-Blöcke (wie in .nix)
        return extract_nix_meta(content)

    lines = content.split("\n")
    in_fm = False
    for line in lines[1:30]:
        if line.strip() == "---":
            if not in_fm:
                in_fm = True
                continue
            else:
                break
        if in_fm and ":" in line:
            key, _, val = line.partition(":")
            meta[key.strip()] = val.strip()

    return meta


def relative_path(abs_path: str, root: str) -> str:
    return abs_path[len(root):].lstrip("/")


def should_exclude(path: Path, root: Path) -> bool:
    rel = path.relative_to(root)
    parts = rel.parts
    for part in parts[:-1]:  # Verzeichnis-Komponenten
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
        return meta["role"]
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

        CREATE INDEX IF NOT EXISTS idx_sf_kind        ON source_files(kind);
        CREATE INDEX IF NOT EXISTS idx_sf_role        ON source_files(module_role);
        CREATE INDEX IF NOT EXISTS idx_sf_layer       ON source_files(layer);

        CREATE VIRTUAL TABLE IF NOT EXISTS source_files_fts USING fts5(
            path,
            kind,
            module_role,
            purpose,
            content,
            content='source_files',
            content_rowid='id',
            tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS sf_fts_insert
        AFTER INSERT ON source_files BEGIN
            INSERT INTO source_files_fts(rowid, path, kind, module_role, purpose, content)
            VALUES (new.id, new.path, new.kind, new.module_role, new.purpose, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS sf_fts_delete
        AFTER DELETE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, path, kind, module_role, purpose, content)
            VALUES ('delete', old.id, old.path, old.kind, old.module_role, old.purpose, old.content);
        END;

        CREATE TRIGGER IF NOT EXISTS sf_fts_update
        AFTER UPDATE ON source_files BEGIN
            INSERT INTO source_files_fts(source_files_fts, rowid, path, kind, module_role, purpose, content)
            VALUES ('delete', old.id, old.path, old.kind, old.module_role, old.purpose, old.content);
            INSERT INTO source_files_fts(rowid, path, kind, module_role, purpose, content)
            VALUES (new.id, new.path, new.kind, new.module_role, new.purpose, new.content);
        END;
    """)
    conn.commit()


def index_file(conn: sqlite3.Connection, path: Path, root: str, dry_run: bool = False) -> bool:
    rel = relative_path(str(path), root)
    kind = KIND_MAP.get(path.suffix, "other")

    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"  SKIP {rel}: {e}", file=sys.stderr)
        return False

    if kind == "nix":
        meta = extract_nix_meta(content)
    else:
        meta = extract_md_frontmatter(content)

    layer = None
    raw_layer = meta.get("layer")
    if raw_layer and str(raw_layer).isdigit():
        layer = int(raw_layer)

    module_role = infer_module_role(rel, meta)
    purpose = meta.get("purpose", "")
    size = len(content.encode("utf-8"))
    mtime = path.stat().st_mtime

    if dry_run:
        print(f"  DRY {kind:4} [{layer or '-'}] {module_role:10} {rel}")
        return True

    conn.execute("""
        INSERT INTO source_files (path, kind, layer, module_role, purpose, content, size_bytes, mtime, indexed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, unixepoch())
        ON CONFLICT(path) DO UPDATE SET
            kind        = excluded.kind,
            layer       = excluded.layer,
            module_role = excluded.module_role,
            purpose     = excluded.purpose,
            content     = excluded.content,
            size_bytes  = excluded.size_bytes,
            mtime       = excluded.mtime,
            indexed_at  = unixepoch()
    """, (rel, kind, layer, module_role, purpose, content, size, mtime))
    return True


def main():
    parser = argparse.ArgumentParser(description="Indexiert /etc/nixos in nixos_docs.sqlite")
    parser.add_argument("--db",      default=DB_PATH,    help="Pfad zur SQLite-DB")
    parser.add_argument("--root",    default=NIXOS_ROOT, help="NixOS-Root-Verzeichnis")
    parser.add_argument("--dry-run", action="store_true", help="Nur anzeigen, nichts schreiben")
    args = parser.parse_args()

    print(f"Indexer: {args.root} → {args.db}")
    if args.dry_run:
        print("DRY-RUN — keine Änderungen an der DB")

    conn = sqlite3.connect(args.db)
    ensure_schema(conn)

    total = 0
    ok = 0
    t0 = time.time()

    for path in iter_files(args.root):
        total += 1
        if index_file(conn, path, args.root, dry_run=args.dry_run):
            ok += 1

    if not args.dry_run:
        conn.commit()

        # Stale Einträge entfernen (Dateien die nicht mehr existieren oder excluded sind)
        indexed_paths = set()
        for path in iter_files(args.root):
            indexed_paths.add(relative_path(str(path), args.root))

        all_db_paths = {
            row[0] for row in conn.execute("SELECT path FROM source_files").fetchall()
        }
        stale = all_db_paths - indexed_paths
        if stale:
            conn.executemany("DELETE FROM source_files WHERE path = ?", [(p,) for p in stale])
            conn.commit()
            print(f"Stale Einträge entfernt: {len(stale)}")

        # FTS5 optimize nach Bulk-Insert
        conn.execute("INSERT INTO source_files_fts(source_files_fts) VALUES('optimize')")
        conn.commit()

        # Statistik
        count = conn.execute("SELECT COUNT(*) FROM source_files").fetchone()[0]
        print(f"\nFertig: {ok}/{total} Dateien indexiert in {time.time()-t0:.1f}s")
        print(f"source_files gesamt: {count} Einträge")
    else:
        print(f"\nDRY-RUN: {ok}/{total} Dateien würden indexiert")

    conn.close()


if __name__ == "__main__":
    main()
