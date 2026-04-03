# Testing Rules

## Test Suites

| Package | Command | Count | Time |
|---------|---------|-------|------|
| core | `cd core && npm test` | 39 | ~1s |
| local | `cd local && npm test` | 22 | ~1s |
| app | `cd app && flutter analyze` | static | ~5s |

## When to Run Tests

- **Always** before committing (all three suites)
- After modifying `core/src/` — run core tests
- After modifying `local/src/` — run both core and local tests (local depends on core)
- After modifying `app/lib/` — run flutter analyze
- After modifying MCP tools — run core tests (tools are tested there)

## Test Patterns

- Core tests use in-memory SQLite (`:memory:`) — no fixtures to manage
- Local tests use supertest against the Hono app
- Flutter uses `flutter analyze` for static analysis; integration tests exist but run manually on macOS
