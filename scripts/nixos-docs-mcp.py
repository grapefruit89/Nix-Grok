#!/usr/bin/env python3
# ---
# meta:
#   role: script
#   purpose: MCP-Server für nixos_docs.sqlite — FTS5 über stdio (keine lokale KI)
#   docs:
#     - docs/guides/GUIDE-knowledge-db.md
#     - docs/guides/ANTIPATTERNS.md#lokale-ki
#   tags:
#     - mcp
#     - sqlite
#     - fts5
# ---
"""NixOS-Docs MCP Server — FTS5 über stdio (JSON-RPC 2.0). Keine Embeddings auf q958."""
import json
import sqlite3
import sys

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


TOOLS = [
    {
        "name": "fts_search",
        "description": "FTS5/BM25 in chat_insights — destilliertes Chat-Wissen",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "search_chunks",
        "description": "FTS5 in doc_chunks — Markdown-Abschnitte (##/###) mit heading und anchor",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "role": {"type": "string"},
                "status": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "list_insights",
        "description": "chat_insights filtern nach theme / status / agent",
        "inputSchema": {
            "type": "object",
            "properties": {
                "theme": {"type": "string"},
                "status": {"type": "string"},
                "agent": {"type": "string"},
                "limit": {"type": "integer", "default": 20},
            },
        },
    },
    {
        "name": "list_doc_links",
        "description": "Link-Graph: meta.docs, betrifft, siehe_auch",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "direction": {"type": "string", "enum": ["from", "to", "both"], "default": "both"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "query",
        "description": "Beliebige SQL SELECT auf nixos_docs.sqlite",
        "inputSchema": {
            "type": "object",
            "properties": {"sql": {"type": "string"}},
            "required": ["sql"],
        },
    },
    {
        "name": "search_nix",
        "description": "FTS5 in .nix Konfigurationsdateien",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "layer": {"type": "integer", "minimum": 0, "maximum": 90},
                "role": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "search_docs",
        "description": "FTS5 in .md Dateien (ganze Datei). Filter: role, status, tag",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "role": {"type": "string"},
                "status": {"type": "string"},
                "tag": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "search_all",
        "description": "FTS5 über .nix + .md + .sh",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 15},
            },
            "required": ["query"],
        },
    },
]


def tool_fts_search(args):
    q = args.get("query", "")
    limit = int(args.get("limit", 10))
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT i.id, i.theme, i.agent, i.title, i.content, i.status, i.rollout_stufe, "
            "       bm25(chat_insights_fts) AS rank "
            "FROM chat_insights_fts "
            "JOIN chat_insights i ON i.id = chat_insights_fts.rowid "
            "WHERE chat_insights_fts MATCH ? ORDER BY rank LIMIT ?",
            (q, limit),
        ).fetchall()
        return [dict(r) for r in rows]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def _chunk_filters(role, status):
    where = ["doc_chunks_fts MATCH ?"]
    joins = [
        "JOIN doc_chunks c ON c.id = doc_chunks_fts.rowid",
        "JOIN source_files sf ON sf.id = c.source_file_id",
        "LEFT JOIN doc_meta dm ON dm.source_file_id = sf.id",
    ]
    if role:
        where.append("(sf.module_role = ? OR dm.role = ?)")
    if status:
        where.append("dm.status = ?")
    return joins, where


def tool_search_chunks(args):
    q = args.get("query", "")
    limit = int(args.get("limit", 10))
    role = args.get("role")
    status = args.get("status")
    joins, where = _chunk_filters(role, status)
    params = [q]
    if role:
        params.extend([role, role])
    if status:
        params.append(status)
    params.append(limit)
    conn = get_db()
    try:
        sql = (
            "SELECT c.id, c.path, c.heading, c.anchor, c.level, "
            "       snippet(doc_chunks_fts, 3, '[', ']', '…', 24) AS snippet, "
            "       bm25(doc_chunks_fts) AS rank, dm.status, dm.purpose "
            f"FROM doc_chunks_fts {' '.join(joins)} "
            f"WHERE {' AND '.join(where)} ORDER BY rank LIMIT ?"
        )
        return [dict(r) for r in conn.execute(sql, params).fetchall()]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def tool_list_doc_links(args):
    path = args.get("path", "")
    direction = args.get("direction", "both")
    conn = get_db()
    try:
        results = []
        if direction in ("from", "both"):
            rows = conn.execute(
                "SELECT from_path, to_path, link_type, anchor FROM doc_links WHERE from_path = ?",
                (path,),
            ).fetchall()
            results.extend([{"direction": "out", **dict(r)} for r in rows])
        if direction in ("to", "both"):
            rows = conn.execute(
                "SELECT from_path, to_path, link_type, anchor FROM doc_links WHERE to_path = ?",
                (path,),
            ).fetchall()
            results.extend([{"direction": "in", **dict(r)} for r in rows])
        return results
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def tool_list_insights(args):
    where, params = [], []
    for col in ("theme", "status", "agent"):
        if args.get(col):
            where.append(f"{col} = ?")
            params.append(args[col])
    sql = "SELECT id, theme, agent, title, content, status, rollout_stufe FROM chat_insights"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY id DESC LIMIT ?"
    params.append(int(args.get("limit", 20)))
    conn = get_db()
    try:
        return [dict(r) for r in conn.execute(sql, params).fetchall()]
    finally:
        conn.close()


def tool_query(args):
    sql = args.get("sql", "").strip()
    if not sql.upper().startswith("SELECT"):
        return {"error": "Nur SELECT-Statements erlaubt"}
    conn = get_db()
    try:
        return [dict(r) for r in conn.execute(sql).fetchall()]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def _sf_search(query, kind_filter, role_filter, layer_filter, status, tag, limit):
    conn = get_db()
    try:
        where_parts = ["source_files_fts MATCH ?"]
        params = [query]
        joins = ["JOIN source_files sf ON sf.id = source_files_fts.rowid"]

        if status or tag:
            joins.append("LEFT JOIN doc_meta dm ON dm.source_file_id = sf.id")
        if tag:
            joins.append("JOIN doc_tags dt ON dt.source_file_id = sf.id")

        if kind_filter:
            where_parts.append("sf.kind = ?")
            params.append(kind_filter)
        if role_filter:
            where_parts.append("sf.module_role = ?")
            params.append(role_filter)
        if layer_filter is not None:
            where_parts.append("sf.layer = ?")
            params.append(layer_filter)
        if status:
            where_parts.append("dm.status = ?")
            params.append(status)
        if tag:
            where_parts.append("dt.tag = ?")
            params.append(tag)

        params.append(limit)
        sql = (
            "SELECT sf.id, sf.path, sf.kind, sf.layer, sf.module_role, sf.purpose, "
            "       dm.status, dm.error_pattern, dm.quick_fix, "
            "       snippet(source_files_fts, 4, '[', ']', '…', 20) AS snippet, "
            "       bm25(source_files_fts) AS rank "
            f"FROM source_files_fts {' '.join(joins)} "
            f"WHERE {' AND '.join(where_parts)} ORDER BY rank LIMIT ?"
        )
        return [dict(r) for r in conn.execute(sql, params).fetchall()]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def tool_search_nix(args):
    return _sf_search(
        query=args.get("query", ""),
        kind_filter="nix",
        role_filter=args.get("role"),
        layer_filter=args.get("layer"),
        status=None,
        tag=None,
        limit=int(args.get("limit", 10)),
    )


def tool_search_docs(args):
    return _sf_search(
        query=args.get("query", ""),
        kind_filter="md",
        role_filter=args.get("role"),
        layer_filter=None,
        status=args.get("status"),
        tag=args.get("tag"),
        limit=int(args.get("limit", 10)),
    )


def tool_search_all(args):
    return _sf_search(
        query=args.get("query", ""),
        kind_filter=None,
        role_filter=None,
        layer_filter=None,
        status=None,
        tag=None,
        limit=int(args.get("limit", 15)),
    )


TOOL_HANDLERS = {
    "fts_search": tool_fts_search,
    "search_chunks": tool_search_chunks,
    "list_insights": tool_list_insights,
    "list_doc_links": tool_list_doc_links,
    "query": tool_query,
    "search_nix": tool_search_nix,
    "search_docs": tool_search_docs,
    "search_all": tool_search_all,
}


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def handle(msg):
    method = msg.get("method", "")
    mid = msg.get("id")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "nixos-docs-mcp", "version": "1.4.0"},
                "capabilities": {"tools": {}},
            },
        })
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
    elif method == "tools/call":
        p = msg.get("params", {})
        name = p.get("name", "")
        handler = TOOL_HANDLERS.get(name)
        if not handler:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"Unbekanntes Tool: {name}"}})
            return
        try:
            result = handler(p.get("arguments", {}))
            send({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}]},
            })
        except Exception as e:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32000, "message": str(e)}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"Unbekannte Methode: {method}"}})


if __name__ == "__main__":
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            handle(json.loads(line))
        except json.JSONDecodeError:
            pass