#!/usr/bin/env python3
# ---
# meta:
#   role: script
#   purpose: MCP-Server für nixos_docs.sqlite — FTS5 + sqlite-vec + Hybrid-RRF über stdio
#   docs:
#     - docs/adr/011-unified-port-uid-schema.md
#   tags:
#     - mcp
#     - sqlite
#     - fts5
#     - vector
#     - hybrid-search
# ---
"""NixOS-Docs MCP Server — FTS5 + sqlite-vec + Hybrid-RRF über stdio (JSON-RPC 2.0)"""
import sys, json, sqlite3, glob, struct

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "/var/lib/nixos-docs-mcp/nixos_docs.sqlite"

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
            conn.load_extension(VEC_SO[:-3])  # sqlite3 appends .so itself
            conn.enable_load_extension(False)
        except Exception:
            pass
    return conn

# ── Tool-Definitionen ──────────────────────────────────────────────────────────
TOOLS = [
    {
        "name": "fts_search",
        "description": "Volltextsuche (FTS5/BM25) in chat_insights — Wissen, ADRs, Entscheidungen des NixOS-Homelab",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "FTS5-Syntax: Wörter, Phrasen in \"\", AND/OR/NOT, Prefix*"},
                "limit": {"type": "integer", "default": 10}
            },
            "required": ["query"]
        }
    },
    {
        "name": "hybrid_search",
        "description": (
            "Hybrid-Suche (Reciprocal Rank Fusion) — kombiniert FTS5-BM25 mit sqlite-vec KNN. "
            "Besser als reine FTS5- oder Vektor-Suche: findet auch semantisch ähnliche Treffer "
            "ohne exakte Keyword-Übereinstimmung. Ohne Embedding fällt es auf FTS5 zurück."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query":     {"type": "string", "description": "Suchbegriff (FTS5)"},
                "embedding": {
                    "type": "array",
                    "items": {"type": "number"},
                    "description": "Optional: float[384] Vektor für semantische KNN-Komponente"
                },
                "limit":     {"type": "integer", "default": 10}
            },
            "required": ["query"]
        }
    },
    {
        "name": "list_insights",
        "description": "chat_insights filtern nach theme / status / agent",
        "inputSchema": {
            "type": "object",
            "properties": {
                "theme":  {"type": "string", "description": "nix_os | unraid"},
                "status": {"type": "string", "description": "accepted | proposed | antipattern | reference"},
                "agent":  {"type": "string", "description": "claude | grok | deepseek | user_meta | consensus"},
                "limit":  {"type": "integer", "default": 20}
            }
        }
    },
    {
        "name": "query",
        "description": "Beliebige SQL SELECT-Abfrage auf nixos_docs.sqlite. FTS5 via 'chat_insights_fts MATCH ?'.",
        "inputSchema": {
            "type": "object",
            "properties": {"sql": {"type": "string"}},
            "required": ["sql"]
        }
    },
    {
        "name": "vec_search",
        "description": "Reine KNN-Vektorsuche (sqlite-vec) in insight_embeddings. Embedding muss float[384] sein.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "embedding": {"type": "array", "items": {"type": "number"}, "description": "float[384] Vektor"},
                "limit":     {"type": "integer", "default": 5}
            },
            "required": ["embedding"]
        }
    }
]

# ── Tool-Implementierungen ─────────────────────────────────────────────────────
def tool_fts_search(args):
    q     = args.get("query", "")
    limit = int(args.get("limit", 10))
    conn  = get_db()
    try:
        rows = conn.execute(
            "SELECT i.id, i.theme, i.agent, i.title, i.content, i.status, i.rollout_stufe, "
            "       bm25(chat_insights_fts) AS rank "
            "FROM chat_insights_fts "
            "JOIN chat_insights i ON i.id = chat_insights_fts.rowid "
            "WHERE chat_insights_fts MATCH ? "
            "ORDER BY rank LIMIT ?",
            (q, limit)
        ).fetchall()
        return [dict(r) for r in rows]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


def tool_hybrid_search(args):
    """Reciprocal Rank Fusion: FTS5-BM25 + sqlite-vec KNN.

    RRF-Score = 1/(k+rank_fts) + 1/(k+rank_vec), k=60 (empirisch optimal).
    Ohne Embedding: nur FTS5. Ohne vec_so: nur FTS5.
    """
    q         = args.get("query", "")
    embedding = args.get("embedding")
    limit     = int(args.get("limit", 10))
    k         = 60

    conn = get_db()
    try:
        # ── FTS5 ───────────────────────────────────────────────────────────────
        fts_rows = conn.execute(
            "SELECT i.id, i.theme, i.agent, i.title, i.content, i.status, i.rollout_stufe, "
            "       bm25(chat_insights_fts) AS bm25_rank "
            "FROM chat_insights_fts "
            "JOIN chat_insights i ON i.id = chat_insights_fts.rowid "
            "WHERE chat_insights_fts MATCH ? "
            "ORDER BY bm25_rank LIMIT ?",
            (q, limit * 3)
        ).fetchall()

        fts_rrf   = {row["id"]: 1.0 / (k + pos + 1) for pos, row in enumerate(fts_rows)}
        row_cache = {row["id"]: dict(row) for row in fts_rows}

        # ── sqlite-vec KNN (optional) ──────────────────────────────────────────
        vec_rrf = {}
        if embedding and VEC_SO and len(embedding) == 384:
            blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
            vec_rows = conn.execute(
                "SELECT i.id, i.title, i.content, i.status, v.distance "
                "FROM insight_embeddings v "
                "JOIN chat_insights i ON i.id = v.insight_id "
                "WHERE v.embedding MATCH ? AND k = ? "
                "ORDER BY v.distance",
                (blob, limit * 3)
            ).fetchall()
            vec_rrf = {row["id"]: 1.0 / (k + pos + 1) for pos, row in enumerate(vec_rows)}
            for row in vec_rows:
                if row["id"] not in row_cache:
                    row_cache[row["id"]] = dict(row)

        # ── RRF-Merge ─────────────────────────────────────────────────────────
        all_ids = set(fts_rrf) | set(vec_rrf)
        ranked  = sorted(all_ids, key=lambda i: fts_rrf.get(i, 0) + vec_rrf.get(i, 0), reverse=True)

        results = []
        for doc_id in ranked[:limit]:
            row = row_cache[doc_id].copy()
            row["rrf_score"] = round(fts_rrf.get(doc_id, 0) + vec_rrf.get(doc_id, 0), 6)
            row["sources"]   = (
                "fts+vec" if doc_id in fts_rrf and doc_id in vec_rrf
                else "fts" if doc_id in fts_rrf
                else "vec"
            )
            results.append(row)
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
    if len(embedding) != 384:
        return {"error": f"Benötige float[384], erhalten: {len(embedding)}"}
    limit    = int(args.get("limit", 5))
    vec_blob = struct.pack(f"{len(embedding)}f", *[float(x) for x in embedding])
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT i.id, i.title, i.content, i.status, v.distance "
            "FROM insight_embeddings v "
            "JOIN chat_insights i ON i.id = v.insight_id "
            "WHERE v.embedding MATCH ? AND k = ? "
            "ORDER BY v.distance",
            (vec_blob, limit)
        ).fetchall()
        return [dict(r) for r in rows]
    except Exception as e:
        return {"error": str(e)}
    finally:
        conn.close()


TOOL_HANDLERS = {
    "fts_search":    tool_fts_search,
    "hybrid_search": tool_hybrid_search,
    "list_insights": tool_list_insights,
    "query":         tool_query,
    "vec_search":    tool_vec_search,
}

# ── MCP JSON-RPC 2.0 stdio Loop ───────────────────────────────────────────────
def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

def handle(msg):
    method = msg.get("method", "")
    mid    = msg.get("id")
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2024-11-05",
            "serverInfo": {"name": "nixos-docs-mcp", "version": "1.2.0"},
            "capabilities": {"tools": {}}
        }})
    elif method == "notifications/initialized":
        pass
    elif method == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
    elif method == "tools/call":
        p       = msg.get("params", {})
        name    = p.get("name", "")
        handler = TOOL_HANDLERS.get(name)
        if not handler:
            send({"jsonrpc": "2.0", "id": mid,
                  "error": {"code": -32601, "message": f"Unbekanntes Tool: {name}"}})
            return
        try:
            result = handler(p.get("arguments", {}))
            send({"jsonrpc": "2.0", "id": mid, "result": {
                "content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}]
            }})
        except Exception as e:
            send({"jsonrpc": "2.0", "id": mid,
                  "error": {"code": -32000, "message": str(e)}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid,
              "error": {"code": -32601, "message": f"Unbekannte Methode: {method}"}})

if __name__ == "__main__":
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            handle(json.loads(line))
        except json.JSONDecodeError:
            pass
