#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { DuckDBInstance } from "@duckdb/node-api";

const dbPath =
  process.env.NIXOS_DOCS_DB ||
  `${process.env.HOME}/.local/share/nix-grok/nixos_docs.db`;

async function withDb(fn) {
  const instance = await DuckDBInstance.create(dbPath, {
    access_mode: "READ_ONLY",
  });
  const conn = await instance.connect();
  try {
    return await fn(conn);
  } finally {
    conn.closeSync();
    instance.closeSync();
  }
}

function rowsToText(rows) {
  return JSON.stringify(
    rows,
    (_, value) => (typeof value === "bigint" ? Number(value) : value),
    2,
  );
}

const server = new McpServer({
  name: "nixos-docs",
  version: "1.0.0",
});

server.tool(
  "nixos_docs_query",
  [
    "Run read-only SQL against the NixOS docs knowledge index (DuckDB).",
    "Tables: documents (id, path, title, status, content, derived_from),",
    "document_tags (document_id, tag), bundles, bundles_link.",
    "Examples:",
    "  SELECT title, path FROM documents WHERE status = 'antipattern';",
    "  SELECT path FROM documents WHERE path LIKE '%.nix';",
    "  SELECT d.title, t.tag FROM documents d JOIN document_tags t ON d.id = t.document_id;",
  ].join(" "),
  {
    sql: z.string().describe("Read-only DuckDB SQL query"),
  },
  async ({ sql }) => {
    if (!dbPath) {
      return {
        content: [{ type: "text", text: "NIXOS_DOCS_DB is not set." }],
        isError: true,
      };
    }

    const normalized = sql.trim().toLowerCase();
    if (
      /(^|;)\s*(insert|update|delete|drop|create|alter|attach|detach|copy|pragma)\b/.test(
        normalized,
      )
    ) {
      return {
        content: [
          {
            type: "text",
            text: "Only read-only SELECT/WITH/SHOW/DESCRIBE/EXPLAIN queries are allowed.",
          },
        ],
        isError: true,
      };
    }

    try {
      const rows = await withDb(async (conn) => {
        const reader = await conn.runAndReadAll(sql);
        return reader.getRowObjectsJson();
      });
      return { content: [{ type: "text", text: rowsToText(rows) }] };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Query failed on ${dbPath}: ${error?.message || error}`,
          },
        ],
        isError: true,
      };
    }
  },
);

server.tool(
  "nixos_docs_schema",
  "List tables and columns in nixos_docs.db.",
  {},
  async () => {
    try {
      const rows = await withDb(async (conn) => {
        const tablesReader = await conn.runAndReadAll("SHOW TABLES");
        const tables = tablesReader.getRowObjectsJson().map((row) => row.name);
        const schema = [];
        for (const table of tables) {
          const describeReader = await conn.runAndReadAll(
            `DESCRIBE ${table}`,
          );
          schema.push({
            table,
            columns: describeReader.getRowObjectsJson(),
          });
        }
        return schema;
      });
      return { content: [{ type: "text", text: rowsToText(rows) }] };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Schema read failed on ${dbPath}: ${error?.message || error}`,
          },
        ],
        isError: true,
      };
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);