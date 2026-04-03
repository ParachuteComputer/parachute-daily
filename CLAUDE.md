# Parachute Daily — Flutter App

Voice journaling app with offline-first architecture. Connects to a Parachute Vault for storage, search, and AI agent access.

## Architecture

```
Flutter App  →  Vault HTTP API  →  SQLite (notes/tags/links)
                                        ↑
Claude/AI    →  Vault MCP  ─────────────┘
```

The app talks to a Parachute Vault over HTTP. The vault owns all data (notes, tags, links, attachments) and MCP tools. See [parachute-vault](https://github.com/ParachuteComputer/parachute-vault) for server/MCP details.

## App Views (Three Tabs)

| Tab | Query | Description |
|-----|-------|-------------|
| **Digest** | `#digest AND NOT #archived` | AI briefs, clipped content |
| **Daily** | `#daily`, grouped by date | Voice memos, typed notes |
| **Docs** | `#doc*`, searchable | Blog drafts, meeting notes, lists |

## Running

```bash
cd app && flutter run -d macos       # desktop
cd app && flutter run -d <device>    # android
cd app && flutter analyze            # static analysis
```

## Workflow

Feature branches + PRs for all changes. Run `flutter analyze` before committing. See `.claude/rules/workflow.md`.

See `app/CLAUDE.md` for detailed Flutter conventions, directory structure, and gotchas.
