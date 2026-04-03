# MCP Tools Reference

11 tools defined in `core/src/mcp.ts`, served via both stdio and HTTP transports.

## Tool List

| Tool | Purpose | Key Params |
|------|---------|------------|
| `create-note` | Create note with tags | `content`, `tags[]`, `path` |
| `update-note` | Update content or path | `id`, `content`, `path` |
| `delete-note` | Delete note + tags + links | `id` |
| `read-notes` | Query by tags, dates, pagination | `tags[]`, `exclude_tags[]`, `date_from` (inclusive), `date_to` (exclusive), `limit`, `offset` |
| `search-notes` | Full-text search (FTS5) | `query`, `tags[]`, `limit` |
| `tag-note` | Add tags to a note | `id`, `tags[]` |
| `untag-note` | Remove tags from a note | `id`, `tags[]` |
| `create-link` | Link two notes | `source_id`, `target_id`, `relationship` |
| `delete-link` | Remove a link | `source_id`, `target_id`, `relationship` |
| `get-links` | Get note's connections | `id`, `direction` (outbound/inbound/both) |
| `list-tags` | All tags with counts | (none) |

## Date Range Semantics

- `date_from`: inclusive (`>=`)
- `date_to`: exclusive (`<`)
- To get all of March: `date_from: "2026-03-01"`, `date_to: "2026-04-01"`

## Transports

- **HTTP**: `POST /mcp` on the Hono server (port 1940), session-based
- **stdio**: `npx tsx src/mcp-stdio.ts`, for direct Claude integration

## When Modifying Tools

- Tools are defined in `core/src/mcp.ts` using plain JSON Schema (not Zod)
- `QueryOpts` type in `core/src/types.ts` — add new params there first
- Store layer in `core/src/notes.ts` — implement the query logic
- Run `cd core && npm test` — tool registration is tested
