# Security Rules

## Sensitive Files — Never Read or Edit

- `~/.parachute/server.yaml` — contains hashed API keys
- `.env`, `.env.*` — environment secrets
- Any file matching `*credentials*`, `*secret*`

## API Keys

- Never log, print, or include API keys in commits
- Keys are generated via `POST /api/auth/keys` (localhost only)
- Format: `para_<32 chars>`, ID: `k_<12 chars>`
- Stored as SHA-256 hashes in server.yaml

## Auth Model

- `remote` mode (default): localhost bypasses auth, remote requires API key
- `always` mode: all requests need a key
- `disabled` mode: dev only, never in production
- Auth header: `Authorization: Bearer para_...` or `X-API-Key: para_...`

## When Touching Auth Code

- Never weaken auth checks (e.g., removing isLocalhost guards)
- Timing-safe comparison for key verification (crypto.timingSafeEqual)
- Config file permissions: 0o600 (owner read/write only)
