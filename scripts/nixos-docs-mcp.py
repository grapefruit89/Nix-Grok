#!/usr/bin/env python3
# ---
# meta:
#   role: script
#   purpose: MCP-Server für nixos_docs.sqlite — FTS5 + sqlite-vec + Hybrid-RRF über stdio
#   docs:
#     - docs/guides/GUIDE-knowledge-db.md
#   tags:
#     - mcp
#     - sqlite
#     - fts5
#     - vector
#     - hybrid-search
# ---
"""NixOS-Docs MCP Server — FTS5 + sqlite-vec + Hybrid-RRF über stdio (JSON-RPC 2.0)"""
import glob
import json
import sqlite3
import struct
import sys

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"
RRF_K = 60
EMBED_DIM = 384


def find_vec_so():
    hits = sorted(glob.glob("/nix/store/*/lib/vec0.so"))
    return hits[-1] if hits else None


VEC_SO = find_vec_so()


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    if VEC_SO:
        try:
            conn.enable_load_extension(True)
            conn.load_extension(VEC_SO[:-3])
            conn.enable_load_extension(False)
        except Exception:
            pass
    return conn


def rrf_merge(fts_rows, vec_rows, id_key="id", limit=10):
    fts_rrf = {row[id_key]: 1.0 / (RRF_K + pos + 1) for pos, row in enumerate(fts_rows)}
    vec_rrf = {row[id_key]: 1.0 / (RRF_K + pos + 1) for pos, row in enumerate(vec_rows)}
    row_cache = {row[id_key]: dict(row) for row in fts_rows}
    for row in vec_rows:
        if row[id_key] not in row_cache:
            row_cache[row[id_key]] = dict(row)

    all_ids = set(fts_rrf) | set(vec_rrf)
    ranked = sorted(all_ids, key=lambda i: fts_rrf.get(i, 0) + vec_rrf.get(i, 0), reverse=True)

    results = []
    for doc_id in ranked[:limit]:
        row = row_cache[doc_id].copy()
        row["rrf_score"] = round(fts_rrf.get(doc_id, 0) + vec_rrf.get(doc_id, 0), 6)
        row["sources"] = (
            "fts+vec" if doc_id in fts_rrf and doc_id in vec_rrf
            else "fts" if doc_id in fts_rrf
            else "vec"
        )
        results.append(row)
    return results


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
        "name": "hybrid_search",
        "description": "Hybrid RRF: FTS5 + Vektor in chat_insights",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "embedding": {"type": "array", "items": {"type": "number"}},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "hybrid_search_docs",
        "description": (
            "Hybrid RRF über Markdown-Chunks (ADRs, Guides): doc_chunks_fts + doc_chunk_embeddings. "
            "Besser für semantische Doku-Suche als search_docs (ganze Dateien)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "FTS5-Suchbegriff"},
                "embedding": {"type": "array", "items": {"type": "number"}, "description": "float[384] von Ollama nomic-embed-text"},
                "role": {"type": "string", "description": "adr | guide | learning | doc"},
                "status": {"type": "string", "description": "accepted | current | draft | deprecated"},
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
        "description": "Link-Graph: ausgehende oder eingehende Verknüpfungen (meta.docs, betrifft, siehe_auch)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Repo-relativer Pfad"},
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
        "name": "vec_search",
        "description": "KNN in insight_embeddings (float[384])",
        "inputSchema": {
            "type": "object",
            "properties": {
                "embedding": {"type": "array", "items": {"type": "number"}},
                "limit": {"type": "integer", "default": 5},
            },
            "required": ["embedding"],
        },
    },
    {
        "name": "vec_search_docs",
        "description": "KNN in doc_chunk_embeddings — semantische Suche in Markdown-Abschnitten",
        "inputSchema": {
            "type": "object",
            "properties": {
                "embedding": {"type": "array", "items": {"type": "number"}},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["embedding"],
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


def tool_hybrid_search(args):
    q = args.get("query", "")
    embedding = args.get("embedding")
    limit = int(args.get("limit", 10))
    conn = get_db()
    try:
        fts_rows = conn.execute(
            "SELECT i.id, i.theme, i.agent, i.title, i.content, i.status, i.rollout_stufe "
            "FROM chat_insights_fts "
            "JOIN chat_insights i ON i.id = chat_insights_fts.rowid "
            "WHERE chat_insights_fts MATCH ? "
            "ORDER BY bm25(chat_insights_fts) LIMIT ?",
            (q, limit * 3),
        ).fetchall()

        vec_rows = []
        if embedding and VEC_SO and len(embedding) == EMBED_DIM:
            blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
            vec_rows = conn.execute(
                "SELECT i.id, i.title, i.content, i.status, v.distance "
                "FROM insight_embeddings v "
                "JOIN chat_insights i ON i.id = v.insight_id "
                "WHERE v.embedding MATCH ? AND k = ? ORDER BY v.distance",
                (blob, limit * 3),
            ).fetchall()

        return rrf_merge(fts_rows, vec_rows, id_key="id", limit=limit)
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def _chunk_filters(role, status):
    where = ["doc_chunks_fts MATCH ?"]
    params = []
    joins = [
        "JOIN doc_chunks c ON c.id = doc_chunks_fts.rowid",
        "JOIN source_files sf ON sf.id = c.source_file_id",
        "LEFT JOIN doc_meta dm ON dm.source_file_id = sf.id",
    ]
    if role:
        where.append("(sf.module_role = ? OR dm.role = ?)")
        params.extend([role, role])
    if status:
        where.append("dm.status = ?")
        params.append(status)
    return joins, where, params


def tool_search_chunks(args):
    q = args.get("query", "")
    limit = int(args.get("limit", 10))
    joins, where, params = _chunk_filters(args.get("role"), args.get("status"))
    params = [q] + params + [limit]
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


def tool_hybrid_search_docs(args):
    q = args.get("query", "")
    embedding = args.get("embedding")
    limit = int(args.get("limit", 10))
    joins, where, params = _chunk_filters(args.get("role"), args.get("status"))
    conn = get_db()
    try:
        fts_params = [q]
        if args.get("role"):
            fts_params.extend([args["role"], args["role"]])
        if args.get("status"):
            fts_params.append(args["status"])
        fts_params.append(limit * 3)

        fts_sql = (
            "SELECT c.id, c.path, c.heading, c.anchor, c.content, dm.status, dm.purpose "
            f"FROM doc_chunks_fts {' '.join(joins)} "
            f"WHERE {' AND '.join(where)} ORDER BY bm25(doc_chunks_fts) LIMIT ?"
        )
        fts_rows = conn.execute(fts_sql, fts_params).fetchall()

        vec_rows = []
        if embedding and VEC_SO and len(embedding) == EMBED_DIM:
            blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
            vec_rows = conn.execute(
                "SELECT c.id, c.path, c.heading, c.anchor, c.content, v.distance "
                "FROM doc_chunk_embeddings v "
                "JOIN doc_chunks c ON c.id = v.chunk_id "
                "WHERE v.embedding MATCH ? AND k = ? ORDER BY v.distance",
                (blob, limit * 3),
            ).fetchall()

        return rrf_merge(fts_rows, vec_rows, id_key="id", limit=limit)
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def tool_vec_search_docs(args):
    if not VEC_SO:
        return {"error": "sqlite-vec nicht verfügbar"}
    embedding = args.get("embedding", [])
    if len(embedding) != EMBED_DIM:
        return {"error": f"Benötige float[{EMBED_DIM}], erhalten: {len(embedding)}"}
    limit = int(args.get("limit", 10))
    blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT c.id, c.path, c.heading, c.anchor, "
            "       substr(c.content, 1, 500) AS content_preview, v.distance, dm.status "
            "FROM doc_chunk_embeddings v "
            "JOIN doc_chunks c ON c.id = v.chunk_id "
            "LEFT JOIN doc_meta dm ON dm.path = c.path "
            "WHERE v.embedding MATCH ? AND k = ? ORDER BY v.distance",
            (blob, limit),
        ).fetchall()
        return [dict(r) for r in rows]
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


def tool_vec_search(args):
    if not VEC_SO:
        return {"error": "sqlite-vec nicht verfügbar"}
    embedding = args.get("embedding", [])
    if len(embedding) != EMBED_DIM:
        return {"error": f"Benötige float[{EMBED_DIM}], erhalten: {len(embedding)}"}
    limit = int(args.get("limit", 5))
    blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT i.id, i.title, i.content, i.status, v.distance "
            "FROM insight_embeddings v "
            "JOIN chat_insights i ON i.id = v.insight_id "
            "WHERE v.embedding MATCH ? AND k = ? ORDER BY v.distance",
            (blob, limit),
        ).fetchall()
        return [dict(r) for r in rows]
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
    "hybrid_search": tool_hybrid_search,
    "hybrid_search_docs": tool_hybrid_search_docs,
    "search_chunks": tool_search_chunks,
    "list_insights": tool_list_insights,
    "list_doc_links": tool_list_doc_links,
    "query": tool_query,
    "vec_search": tool_vec_search,
    "vec_search_docs": tool_vec_search_docs,
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
                "serverInfo": {"name": "nixos-docs-mcp", "version": "1.3.0"},
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