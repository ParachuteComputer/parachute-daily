# Parachute Daily

Voice journaling app with offline-first architecture. Connects to a [Parachute Vault](https://github.com/ParachuteComputer/parachute-vault) for storage, search, and AI agent access via MCP.

**Package**: `computer.parachute.daily`

## Architecture

```
User → Flutter App → GraphApiService → Parachute Vault server
            ↓                                    ↓
   Local SQLite cache                    SQLite database
   (offline journal)                     (Notes, Tags, Links, Attachments)
                                                 ↓
                                         MCP endpoint (/mcp)
                                         (Claude / AI agents)
```

**Key principle**: Daily works offline with local SQLite cache. Vault connection enables sync, search, and AI agent access via MCP.

### Navigation

Three-tab layout: **Digest**, **Daily**, **Docs**.

| Tab | Query | Description |
|-----|-------|-------------|
| **Digest** | `#digest AND NOT #archived` | AI briefs, clipped content |
| **Daily** | `#daily`, grouped by date | Voice memos, typed notes |
| **Docs** | `#doc*`, searchable | Blog drafts, meeting notes, lists |

## Directory Structure

```
lib/
├── main.dart                        # App entry, _DailyShell (single screen)
├── core/                            # Shared infrastructure
│   ├── models/                      # Dart data models (Note, etc.)
│   ├── providers/                   # Riverpod state management
│   │   ├── app_state_provider.dart  # Server config, app mode
│   │   ├── voice_input_providers.dart
│   │   ├── streaming_voice_providers.dart
│   │   ├── connectivity_provider.dart
│   │   └── backend_health_provider.dart
│   ├── services/
│   │   ├── graph_api_service.dart   # HTTP client for /api/* endpoints
│   │   ├── file_system_service.dart # Local file I/O
│   │   ├── transcription/           # Audio → text (CANONICAL location)
│   │   ├── vad/                     # Voice activity detection (CANONICAL)
│   │   └── audio_processing/        # Audio filters (CANONICAL)
│   ├── theme/
│   │   ├── design_tokens.dart       # BrandColors (use BrandColors.forest, NOT DesignTokens)
│   │   └── app_theme.dart
│   ├── screens/
│   │   └── note_detail_screen.dart  # Shared note viewer/editor (Digest + Docs)
│   └── widgets/                     # Shared UI components
└── features/
    ├── daily/                       # Voice journaling (offline-capable)
    │   ├── home/                    # HomeScreen — main journal view
    │   ├── journal/                 # Journal CRUD, entry display, local cache
    │   ├── recorder/                # Audio recording & transcription
    │   ├── capture/                 # Photo/handwriting input
    │   └── search/                  # Journal search
    ├── digest/                      # AI-surfaced content inbox
    │   ├── screens/                 # DigestScreen — cards, archive toggle, pinning
    │   └── providers/               # Digest data + grouping providers
    ├── docs/                        # Persistent documents
    │   ├── screens/                 # DocsScreen — grouped by sub-tag, searchable
    │   └── providers/               # Docs data + search providers
    ├── settings/                    # App settings (server URL, vault, transcription, Omi)
    └── onboarding/                  # Setup flow
```

## Data Model

Everything is a **Note**, differentiated by flat **Tags**:

- **Note**: Universal record with id, content, optional path, timestamps
- **Tag**: Simple label (e.g., `#daily`, `#doc`, `#digest`, `#pinned`)
- **Link**: Directed relationship between two notes (e.g., mentions, related-to)
- **Attachment**: File associated with a note (audio, image)

### Built-in Tags

```
#daily      — user-captured content (voice memos, typed notes)
#doc        — persistent documents (blog drafts, grocery lists)
#digest     — AI/system-created content for the user
#pinned     — kept prominent (applies to any note)
#archived   — user is done with this (applies to any note)
#voice      — note was transcribed from voice
```

Tags use optional `/` hierarchy: `#doc/meeting`, `#doc/draft`. The Docs tab queries `LIKE 'doc%'` so sub-tags surface automatically. A note can have multiple tags (e.g., `#daily` + `#doc/meeting` appears in both tabs).

### Server API

The `GraphApiService` and `DailyApiService` target these endpoints on the Parachute Vault server. When a vault name is selected, routes use `/vaults/{name}/api/*` instead of `/api/*`.

| Endpoint | Purpose |
|----------|---------|
| `GET/POST /api/notes` | Query / create notes |
| `GET/PATCH/DELETE /api/notes/:id` | Get / update / delete a note |
| `POST/DELETE /api/notes/:id/tags` | Tag / untag a note |
| `GET /api/notes/:id/links` | Get links for a note |
| `GET /api/tags` | List tags with counts |
| `POST/DELETE /api/links` | Create / delete links |
| `GET /api/search?q=...` | Full-text search (FTS5) |
| `POST /api/storage/upload` | Upload audio/image assets |
| `GET /api/health` | Server health check |
| `GET /vaults` | List available vaults |
| `POST /v1/audio/transcriptions` | Whisper-compatible transcription (via scribe) |

### Offline Cache

All three tabs have offline fallback via `NoteLocalCache` (SQLite). Journal entries also use `PendingEntryQueue` to queue mutations when offline and flush them on reconnect. Digest and Docs cache notes on fetch and read from cache when the server is unreachable.

## Conventions

### Provider Patterns

| Type | Use for | Example |
|------|---------|---------|
| `Provider<T>` | Singleton services | `fileSystemServiceProvider` |
| `FutureProvider<T>.autoDispose` | Async data that should refresh | `selectedJournalProvider` |
| `StateNotifierProvider` | Complex mutable state | `journalRefreshTriggerProvider` |
| `StreamProvider` | Reactive streams | `streamingTranscriptionProvider` |
| `StateProvider` | Simple UI state | `selectedJournalDateProvider` |

**Important**: `ref.listen` must be inside `build()`, never in `initState` or callbacks.

### Theme Colors

Use `BrandColors.forest` (NOT `DesignTokens.forestGreen`). Color tokens are in `lib/core/theme/design_tokens.dart`.

### Service Location

Audio processing services have a SINGLE canonical location:
- VAD: `lib/core/services/vad/`
- Audio processing: `lib/core/services/audio_processing/`
- Transcription: `lib/core/services/transcription/`

### Layout & Overflow Prevention

- **Bottom sheets**: Wrap content between drag handle and buttons in `Flexible` + `SingleChildScrollView`. Pin handle and buttons outside scroll. Max height: `MediaQuery.of(context).size.height * 0.85`.
- **Dialog dimensions**: Never hardcode `width: 400`. Use `ConstrainedBox(constraints: BoxConstraints(maxWidth: 400))`.
- **Chip/tag lists**: Always use `Wrap` (not `Row`) for lists that may grow.
- **Breakpoint widths**: Test at 600px, 601px, 1199px, 1200px — transitions are abrupt.

## Running

```bash
flutter run -d macos       # desktop
flutter run -d <device>    # android
flutter analyze            # static analysis

# Integration tests (macOS, one at a time)
flutter test integration_test/daily_test.dart
```

### Sherpa-ONNX Version Pin

**IMPORTANT**: Pin sherpa_onnx to **1.12.20** via `dependency_overrides`. Version 1.12.21+ has ARM SIGSEGV crash on Daylight DC-1.

## Workflow

**Never push directly to main.** All changes go through feature branches and PRs. Run `flutter analyze` before committing. See `.claude/rules/workflow.md` for full process.

## Gotchas

- `lib/core/` is inlined — do NOT add `parachute_app_core` back as a dependency
- Integration tests share the macOS app process — don't run them in parallel
- First build takes ~90s (pod install + compile), subsequent builds ~15-20s
- Vault server runs on port 1940 by default
- `Wrap` not `Row` for chip lists that may overflow
- Bottom sheets without `SingleChildScrollView` will overflow when keyboard opens
