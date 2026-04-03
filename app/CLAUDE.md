# Parachute Daily — Flutter App

Voice journaling app with offline-first architecture. AI agents plug in via MCP.

**Package**: `io.openparachute.parachute`

---

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

**Key principle**: Daily works offline with local SQLite cache. Vault connection enables sync, search, and AI agent access via MCP. See [parachute-vault](https://github.com/ParachuteComputer/parachute-vault) for server details.

### Navigation

Three-tab layout: **Digest**, **Daily**, **Docs**.

- **Digest** — AI-surfaced content (`#digest AND NOT #archived`)
- **Daily** — User captures (`#daily`), grouped by date
- **Docs** — Persistent notes (`#doc`), searchable

---

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
│   └── widgets/                     # Shared UI components
└── features/
    ├── daily/                       # Voice journaling (offline-capable)
    │   ├── home/                    # HomeScreen — main journal view
    │   ├── journal/                 # Journal CRUD, entry display, local cache
    │   ├── recorder/                # Audio recording & transcription
    │   ├── capture/                 # Photo/handwriting input
    │   └── search/                  # Journal search
    ├── settings/                    # App settings (server URL, transcription, Omi device)
    └── onboarding/                  # Setup flow
```

---

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

The `GraphApiService` targets these endpoints on the Parachute Vault server:

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

### Offline Cache

Journal entries are cached locally via `JournalLocalCache` (SQLite). The `PendingEntryQueue` queues mutations when offline and flushes them when the server is reachable.

---

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

Use `BrandColors.forest` (NOT `DesignTokens.forestGreen`). Color tokens are in `core/theme/design_tokens.dart`.

### Service Location

Audio processing services have a SINGLE canonical location:
- VAD: `core/services/vad/`
- Audio processing: `core/services/audio_processing/`
- Transcription: `core/services/transcription/`

### Layout & Overflow Prevention

- **Bottom sheets**: Wrap content between drag handle and buttons in `Flexible` + `SingleChildScrollView`. Pin handle and buttons outside scroll. Max height: `MediaQuery.of(context).size.height * 0.85`.
- **Dialog dimensions**: Never hardcode `width: 400`. Use `ConstrainedBox(constraints: BoxConstraints(maxWidth: 400))`.
- **Chip/tag lists**: Always use `Wrap` (not `Row`) for lists that may grow.
- **Breakpoint widths**: Test at 600px, 601px, 1199px, 1200px — transitions are abrupt.

---

## Running

```bash
# Desktop development
flutter run -d macos

# Vault server (separate terminal, see parachute-vault repo)
# parachute vault init && parachute vault create default

# Static analysis
flutter analyze

# Integration tests (macOS, one at a time)
flutter test integration_test/daily_test.dart
```

### Sherpa-ONNX Version Pin

**IMPORTANT**: Pin sherpa_onnx to **1.12.20** via `dependency_overrides`. Version 1.12.21+ has ARM SIGSEGV crash on Daylight DC-1.

---

## Gotchas

- `core/` is inlined — do NOT add `parachute_app_core` back as a dependency
- Integration tests share the macOS app process — don't run them in parallel
- First build takes ~90s (pod install + compile), subsequent builds ~15-20s
- Vault server runs on port 1940 by default
- `Wrap` not `Row` for chip lists that may overflow
- Bottom sheets without `SingleChildScrollView` will overflow when keyboard opens
