# Testing Rules

## Test Suite

| Package | Command | Type | Time |
|---------|---------|------|------|
| app | `cd app && flutter analyze` | static analysis | ~5s |

## When to Run

- **Always** before committing
- After modifying `app/lib/` — run flutter analyze

## Test Patterns

- Flutter uses `flutter analyze` for static analysis
- Integration tests exist but run manually on macOS: `flutter test integration_test/<test>.dart`
- Integration tests share the macOS app process — don't run them in parallel
