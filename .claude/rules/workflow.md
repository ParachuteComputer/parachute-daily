# Development Workflow

## Branching

- Create a feature branch for every change: `feature/*`, `fix/*`, `docs/*`
- Open a PR with a summary even for self-merge — creates a paper trail
- Squash-merge to keep main clean

## Before Committing

Run static analysis before committing:

```bash
cd app && flutter analyze
```

If it fails, fix before committing. No exceptions.

## Commit Messages

Follow conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`

Keep the first line under 72 characters. Add a body for non-trivial changes explaining *why*, not *what*.

## Deploying to Device

Don't deploy mid-debug. The workflow is:
1. Make changes
2. Run analyze
3. Commit to branch
4. Build and deploy APK
5. Test on device
6. If broken, fix on the branch — don't iterate APK installs without commits

## PRs

Use `gh pr create` with a summary. Include a test plan.
