# Security Rules

## Sensitive Files — Never Read or Edit

- `.env`, `.env.*` — environment secrets
- Any file matching `*credentials*`, `*secret*`

## Auth

The app connects to a Parachute Vault server. API keys are stored in the app's secure storage (SharedPreferences). Never log, print, or include API keys in commits.

Key format: `para_<32 chars>`, ID: `k_<12 chars>`
Auth header: `Authorization: Bearer para_...` or `X-API-Key: para_...`
