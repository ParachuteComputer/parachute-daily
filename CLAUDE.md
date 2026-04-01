# Parachute Daily — Monorepo

Personal note-taking system with voice journaling, AI agents via MCP, and offline-first mobile app.

## Packages

```
core/    — TypeScript library: schema, store, MCP tools (npm: @parachute/core)
local/   — Hono HTTP server + MCP stdio server (npm: @parachute/local)
app/     — Flutter mobile/desktop app (see app/CLAUDE.md for details)
```

## Data Model

Everything is a **Note** differentiated by flat **Tags**. Five tables:

```sql
notes       (id, content, path, created_at, updated_at)
tags        (name)
note_tags   (note_id, tag_name)
attachments (id, note_id, path, mime_type, created_at)
links       (source_id, target_id, relationship, created_at)
```

### Built-in Tags

```
#daily      — user-captured content (voice memos, typed notes)
#doc        — persistent documents (blog drafts, meeting notes, lists)
#digest     — AI/system-created content for the user to consume
#pinned     — kept prominent (applies to any note)
#archived   — user is done with this (applies to any note)
#voice      — note was transcribed from voice
```

Tags use optional `/` hierarchy by convention: `#doc/meeting`, `#doc/draft`. Prefix queries (`LIKE 'doc%'`) match all sub-tags. Notes can have multiple tags — e.g., `#daily` + `#doc/meeting` appears in both Daily and Docs views.

### MCP Tools (11)

`create-note`, `update-note`, `delete-note`, `read-notes`, `search-notes`, `tag-note`, `untag-note`, `create-link`, `delete-link`, `get-links`, `list-tags`

## Running

```bash
# Server (port 1940)
cd local && npx tsx watch src/server.ts

# MCP stdio (for Claude)
cd local && npx tsx src/mcp-stdio.ts

# Flutter app
cd app && flutter run -d macos       # desktop
cd app && flutter run -d <device>    # android

# Tests
cd core && npm test    # 39 tests
cd local && npm test   # 22 tests
cd app && flutter analyze
```

## Architecture

```
Flutter App  →  HTTP API (:1940)  →  SQLite (notes/tags/links)
                                          ↑
Claude/AI    →  MCP stdio server  ────────┘
```

Server at `~/.parachute/daily.db`. Assets at `~/.parachute/daily/assets/`. Auth via API keys in `~/.parachute/server.yaml` (localhost bypasses auth).

## App Views (Three Tabs)

| Tab | Query | Description |
|-----|-------|-------------|
| **Digest** | `#digest AND NOT #archived` | AI briefs, clipped content |
| **Daily** | `#daily`, grouped by date | Voice memos, typed notes |
| **Docs** | `#doc*`, searchable | Blog drafts, meeting notes, lists |
