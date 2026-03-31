# Parachute MCP Setup

Connect Claude (or any MCP-compatible AI) to your Parachute graph.

## Prerequisites

1. Node.js 20+
2. Parachute server initialized: `parachute init`

## Claude Code

Add to your project's `.claude/settings.json` or `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "parachute": {
      "command": "npx",
      "args": ["tsx", "/path/to/parachute-daily/local/src/mcp-stdio.ts"]
    }
  }
}
```

Or if you have the CLI installed:

```json
{
  "mcpServers": {
    "parachute": {
      "command": "parachute",
      "args": ["mcp"]
    }
  }
}
```

## Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "parachute": {
      "command": "parachute",
      "args": ["mcp"],
      "env": {
        "PARACHUTE_DB": "/Users/you/.parachute/daily.db"
      }
    }
  }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PARACHUTE_DB` | `~/.parachute/daily.db` | SQLite database path |

## Available Tools

Once connected, Claude has access to 14 tools:

### Read
- **read-daily-notes** — Journal entries for a date
- **read-recent-notes** — Entries from the past N days
- **search-notes** — Full-text search across entries
- **read-cards** — AI-generated cards for a date
- **read-recent-cards** — Recent cards

### Write
- **create-thing** — Create any thing with tags
- **update-thing** — Update content
- **delete-thing** — Delete a thing
- **write-card** — Write a reflection/summary/briefing card
- **tag-thing** — Apply a tag to a thing
- **untag-thing** — Remove a tag

### Graph
- **link-things** — Create a relationship between things
- **get-related** — Find things connected via edges
- **search-graph** — Traverse the graph from a starting point

## Custom Tools

Apps and agents can register new tools dynamically via the `/api/register` endpoint or by calling `registerTool()` on the store. Tools are stored in the database and automatically available via MCP.

## Verify

```bash
# Check the server is running
parachute status

# Test MCP manually (will block on stdio)
parachute mcp
```
