# Parachute Daily — Architecture Snapshot (2026-03-31)

A personal graph database with a voice journaling interface. You journal into it (voice, text, handwriting, photos), and AI agents can plug in via MCP to read, write, and traverse your graph. The tagline: **"not an AI app — a note-taking app that AI can plug into."**

---

## Three-Layer Architecture

```
+-------------------------------------------------------------+
|  Flutter App (Dart)                                         |
|  Offline-first journal - Local SQLite cache - Omi BLE       |
|  On-device transcription (Sherpa-ONNX) - Riverpod state     |
+------------------------+------------------------------------+
                         | HTTP (port 1940)
+------------------------v------------------------------------+
|  Local Server (TypeScript/Hono)                             |
|  REST API - Auth (API keys) - Asset storage - Transcription |
|  Auto-transcribe on voice entry creation                    |
+------------------------+------------------------------------+
                         | Direct SQLite access
+------------------------v------------------------------------+
|  Core Library (TypeScript)                                  |
|  5-table SQLite schema - FTS5 search - BFS graph traversal  |
|  Declarative tool executor - MCP tool generation            |
+----------------+-------------------------------------------+
                 | MCP stdio
+----------------v-------------------------------------------+
|  Claude / AI Agents                                         |
|  14 builtin tools: read, write, search, traverse, tag, link |
+-------------------------------------------------------------+
```

---

## The Data Model (Everything is a Thing)

5 SQLite tables, Tana-inspired "supertag" typing:

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `things` | Universal record | id (timestamp-based), content, status, created_by |
| `tags` | Schema definitions (supertags) | name, schema_json (FieldDef[]), published_by |
| `thing_tags` | Typing relationship (M:N) | thing_id + tag_name + field_values_json |
| `edges` | Directed graph relationships | source_id, target_id, relationship, properties_json |
| `tools` | Declarative MCP tool definitions | name, input_schema_json, definition_json, enabled |

Plus `things_fts` (FTS5 virtual table with auto-sync triggers) and `schema_version`.

### Builtin Tags

- **daily-note** -- Journal entry (text/voice/handwriting) with fields: entry_type, audio_url, duration_seconds, transcription_status, cleanup_status, date
- **card** -- AI-generated output (reflection/summary/briefing) with fields: card_type, read_at, date
- **person** -- Contact with email, role, notes
- **project** -- Initiative with status, deadline, notes

### Thing ID Format

`YYYY-MM-DD-HH-MM-SS-ffffff` -- timestamp-sortable, human-readable, microsecond-precision with collision counter.

---

## Core Library -- The Graph Engine

### Query System

Dynamic SQL builder supporting:
- Multi-tag AND filtering (one JOIN per tag)
- Tag field filtering via `json_extract()`
- Range filters (`gte`, `lte`, `contains`, `in`)
- Sort by any field (asc/desc)
- Limit/offset pagination
- FTS5 full-text search with graceful error handling

### Graph Traversal

Batch BFS algorithm:
1. Start from a thing, expand outward by depth level
2. One SQL query per depth level (not per node) for efficiency
3. Visited set prevents cycles
4. Post-filters by target tags, direction (outbound/inbound/both), edge type, depth limit

### Tool Executor

Declarative tool definitions stored as data:
- Tools define an `inputSchema` (JSON Schema) and a `definition` with `$param` placeholders
- Executor validates required params + types, resolves `$param` references, dispatches to action handler
- 12 action types: query_things, search_things, traverse, query_edges, upsert_thing, update_thing, delete_thing, create_edge, delete_edge, tag_thing, untag_thing

### 14 Builtin MCP Tools

**Queries:** read-daily-notes, read-recent-notes, search-notes, read-cards, read-recent-cards, get-related, search-graph

**Mutations:** write-card, create-thing, update-thing, delete-thing, tag-thing, untag-thing, link-things

---

## Local Server -- The REST + MCP Bridge

Hono server on port 1940.

### Auth Middleware

Three modes: `remote` (localhost bypasses), `always` (key required), `disabled`. Keys are `para_<32 random>`, stored as SHA-256 hashes in `~/.parachute/server.yaml`. Timing-safe comparison. Hot-reloads config on file mtime change.

### REST API

Things CRUD, Tags CRUD, Edges CRUD, Tools CRUD + execute, FTS search, graph traversal, file storage (upload/download with 100MB limit, extension whitelist, path traversal protection), app registration.

### Auto-Transcription Hook

When a thing is created with `daily-note` tag + `transcription_status: "processing"` + `audio_url`, fires background transcription. Two backends: **Parakeet MLX** (local Python, macOS Apple Silicon) and **API** (OpenAI Whisper/Deepgram compatible). Fallback chain.

### MCP Stdio Server

`mcp-stdio.ts` registers all enabled tools with input schemas via `@modelcontextprotocol/sdk`. Claude and other MCP clients connect via stdio.

---

## Flutter App -- The Journal Interface

### Startup Flow

1. `main()` -- Initialize bindings, run SharedPreferences migrations, set up logging + Sherpa ONNX isolate
2. Initialize Opus codec (iOS/Android), FlutterGemma (embeddings), transcription model download (Android)
3. `MainShell` checks onboarding -> `_DailyShell` (single screen, no tabs)
4. `_DailyShell` initializes Omi BLE services, handles lifecycle (auto-reconnect on resume)

### State Management (Riverpod)

| Layer | Providers | Purpose |
|-------|-----------|---------|
| Config | serverUrlProvider, apiKeyProvider, appModeProvider | Server connection, auth |
| Connectivity | periodicServerHealthProvider, isServerAvailableProvider | 30s health poll, fast-fail/recover |
| Journal | todayJournalProvider, selectedJournalProvider | Cache-first data fetching |
| Recording | DailyRecordingNotifier | Recording state machine |
| Transcription | postHocTranscriptionProvider, streamingTranscriptionProvider | Pipeline state |
| Omi | omiBluetoothServiceProvider, omiCaptureServiceProvider | Device connection |

### Journal Entry Lifecycle

1. **Create** -- User records voice / types text / captures photo / draws handwriting
2. **Local save** -- Para ID generated, entry queued to `PendingEntryQueue` (SharedPreferences), cached in local SQLite
3. **Display** -- Entry appears immediately with "pending" badge
4. **Server sync** -- On connectivity: flush queue -> POST entries -> fetch fresh data -> update cache
5. **Transcription** -- Voice entries: local (Sherpa ONNX on-device) or server (Parakeet/Whisper), polled until complete
6. **Edit/Delete** -- Cached locally as pending_edit/pending_delete, flushed on next connectivity

### Offline Flow

- `JournalLocalCache` -- SQLite with `sync_state` column (synced/pending/pending_delete/pending_edit)
- `PendingEntryQueue` -- SharedPreferences-backed ordered list, persists across restarts
- Cache semantics: `null` from API = network error (use cache), `[]` = authoritative empty (clear cache)
- On offline->online transition: register app -> flush pending queue -> flush pending ops -> refresh providers

### Audio/Transcription Pipeline

```
Microphone -> PCM 16kHz -> Noise Filter (80Hz high-pass) -> VAD (RMS energy)
     |                                                         |
     | <- Record package                    Silence >1s -> Chunk boundary
     v                                                         |
   WAV file ---------------------------+----------------------v
                                       |               Live chunks ->
                               Post-hoc path            Sherpa ONNX ->
                               (stop recording)         Partial results ->
                                       |                     UI stream
                                       v
                            Server available? --Yes--> Upload -> Parakeet/Whisper
                                 |                          -> Poll for result
                                No
                                 |
                                 v
                           Sherpa ONNX (local) -> Result
```

### Omi Device Integration (BLE Wearable)

- `OmiBluetoothService` -- BLE scanning, connection, auto-reconnect
- `OmiCaptureService` -- Two modes: store-and-forward (SD card download) or real-time BLE streaming
- Audio codec: Opus -> decoded via `opus_flutter`/`opus_dart`
- Firmware updates via Nordic DFU
- Button event handling (start/stop recording)

### Input Methods

- **Voice** -- Record -> transcribe (local or server)
- **Text** -- Direct text input
- **Photo** -- Camera/gallery -> Google ML Kit OCR -> text extraction
- **Handwriting** -- Canvas (perfect_freehand) -> OCR -> text extraction

### Theme

Forest green primary, turquoise secondary, cream/charcoal light, nightSurface/nightText dark. Material3 with Inter font.

---

## Test Coverage

| Package | Tests | What's Covered |
|---------|-------|----------------|
| Core | 57 | Thing CRUD, tag validation, edge traversal (BFS), tool execution (all 14 tools), FTS search, MCP generation, input validation |
| Local | 29 | All REST endpoints, error cases (400/404/413), storage upload/download, path traversal rejection, tool validation errors, registration |
| App | 4 integration | App launch, dark mode, Daily-only layout, settings sections |

---

## Key Dependencies

| Dependency | Purpose |
|---|---|
| `better-sqlite3` | SQLite engine (core + local) |
| `hono` + `@hono/node-server` | HTTP server |
| `@modelcontextprotocol/sdk` | MCP stdio server |
| `flutter_riverpod` | State management |
| `sqlite3` + `sqlite3_flutter_libs` | Local journal cache |
| `sherpa_onnx` (pinned 1.12.20) | On-device ASR (Parakeet v3) |
| `flutter_gemma` | On-device embeddings |
| `record` + `just_audio` | Audio capture/playback |
| `flutter_blue_plus` | BLE (Omi device) |
| `opus_dart` / `opus_flutter` | Opus codec (Omi audio) |
| `google_mlkit_text_recognition` | OCR (photo/handwriting) |
| `perfect_freehand` | Handwriting canvas |

---

## File Counts

- **Core**: ~12 TypeScript source files, 1 test file
- **Local**: ~12 TypeScript source files, 1 test file
- **App**: ~130 Dart source files across core/ and features/

## Data Locations

- Server DB: `~/.parachute/daily.db` (SQLite WAL mode)
- Server assets: `~/.parachute/daily/assets/`
- Server config: `~/.parachute/server.yaml`
- App local cache: Documents directory (SQLite)
- App offline queue: SharedPreferences
- Transcription models: `~/Documents/models/parakeet-v3/`

---

## Open Issues

- [#2](https://github.com/OpenParachutePBC/parachute-daily/issues/2) -- Hosted Parachute Daily (build fresh on v2, self-hosting polish first)
- [#3](https://github.com/OpenParachutePBC/parachute-daily/issues/3) -- MCP stdio entrypoint (schemas fixed, needs docs + packaging)
